import Foundation
import Metal
import MetalKit

let APPLEGPU_DISASM_PY_PATH = Bundle.main.bundlePath + "/applegpu/disassemble.py"

@discardableResult func run_shell_command(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()
    
    print("\nCommand: \(command)");
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.standardInput = nil
    task.environment = [:]
    try task.run()
    let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!
    print("Command stdout/stderr:\n\(result)")
    return result
}

print("""

-----------
Environment
-----------
""")
try run_shell_command("xcrun --show-sdk-path")
try run_shell_command("xcrun xcodebuild -version")

let device = MTLCreateSystemDefaultDevice()!
//let gpu_bin_path = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: FileManager.default.temporaryDirectory, create: true)
var gpu_bin_path = FileManager.default.temporaryDirectory;
gpu_bin_path.append(path: String(format: "%06X%06X", arc4random_uniform(65535), arc4random_uniform(65535)))

func create_pipeline_descriptor(lib: MTLLibrary) -> MTLRenderPipelineDescriptor {
    let pipelineDesc = MTLRenderPipelineDescriptor()
    pipelineDesc.vertexFunction = lib.makeFunction(name: "main_vertex")
    pipelineDesc.fragmentFunction = lib.makeFunction(name: "main_fragment")
    pipelineDesc.colorAttachments[0]?.pixelFormat = .rgba8Unorm
    return pipelineDesc
}

func generate_binary_archive(path: URL) throws {
    print("""

    ----------------------
    Harvesting GPU Archive
    ----------------------

    """)
    let lib = device.makeDefaultLibrary()!
    let pipelineDesc = create_pipeline_descriptor(lib: lib)

    let archiveDesc = MTLBinaryArchiveDescriptor()
    let archive = try device.makeBinaryArchive(descriptor: archiveDesc)
    try archive.addRenderPipelineFunctions(descriptor: pipelineDesc)
    try archive.serialize(to: path)
}
try generate_binary_archive(path: gpu_bin_path)

func disasm(path: URL) throws {
    print("""

    -----------------------
    Disassemble GPU Archive
    -----------------------

    """)
    print("""
    GPU Archive Info
    ----------------
    """)
    let path_str = path.path(percentEncoded: false)
    try run_shell_command("xcrun metal-readobj \(path_str)")
    
    let arch = try run_shell_command("xcrun metal-lipo -archs \(path_str) | tr ' ' '\n' | grep applegpu_ | head -n1").trimmingCharacters(in: .whitespacesAndNewlines)
    
    let tmp_gpu_thin_bin_path_str = path_str + "-thin"
    try run_shell_command("xcrun metal-lipo -thin \(arch) \(path_str) -o \(tmp_gpu_thin_bin_path_str)")
    
    let results_str = try run_shell_command("xcrun metal-nm \(tmp_gpu_thin_bin_path_str) | grep \"_agc.main\"")
    let results = results_str.split(separator: /\n/)
    for r in results {
        let parts = r.split(separator: /[ ]/)
        let addr = parts[0];
        let name = "Shader: " + parts[2];
        let footer = String(repeating: "-", count: name.count)
        print("""
        \(name)
        \(footer)
        """)
        try run_shell_command("python3 \(APPLEGPU_DISASM_PY_PATH) \(tmp_gpu_thin_bin_path_str) 0x\(addr)")
    }
}
try disasm(path: gpu_bin_path)

func run_pipeline(path: URL) throws {
    print("""

    -----------------------
    Running Render Pipeline
    -----------------------

    """)
    
    let lib = try! device.makeLibrary(URL: path);
    let pipelineDesc = create_pipeline_descriptor(lib: lib);
    let pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDesc)
    
    
    let WIDTH = 4
    let HEIGHT = 4

    let textureBuf = device.makeBuffer(length: 4 /* 4-bytes (rgba) */ * WIDTH * HEIGHT)!
    let textureDesc = MTLTextureDescriptor()
    textureDesc.storageMode = .shared
    textureDesc.depth = 1
    textureDesc.pixelFormat = .rgba8Unorm
    textureDesc.usage = .renderTarget
    textureDesc.width = WIDTH
    textureDesc.height = HEIGHT
    let output = textureBuf.makeTexture(descriptor: textureDesc, offset: 0, bytesPerRow: 4 * WIDTH)

    let queue = device.makeCommandQueue()!
    let command = queue.makeCommandBuffer()!

    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]!
    color.texture = output
    color.loadAction = .clear
    color.storeAction = .store
    color.clearColor = MTLClearColorMake(0, 0, 0, 0)

    let r = command.makeRenderCommandEncoder(descriptor: renderDesc)!
    r.setRenderPipelineState(pipeline)
    r.drawPrimitives(type: .point, vertexStart: 0, vertexCount: 1)
    r.endEncoding()

    command.commit()
    command.waitUntilCompleted()

    let outputPixels = Array(textureBuf.contents().withMemoryRebound(to: (UInt8, UInt8, UInt8, UInt8).self, capacity: WIDTH * HEIGHT) {
        UnsafeBufferPointer(start: $0, count: WIDTH * HEIGHT)
    })

    func printOutputPixels(_ arr: Array<(UInt8, UInt8, UInt8, UInt8)>) {
        for y in 0..<HEIGHT {
            var r: [UInt8] = []
            for x in 0..<WIDTH {
                r.append(arr[y * WIDTH + x].1)
            }
            print(r)
        }

    }
    printOutputPixels(outputPixels)
}
try run_pipeline(path: gpu_bin_path)

