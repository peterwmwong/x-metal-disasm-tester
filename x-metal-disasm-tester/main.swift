import Foundation
import Metal
import MetalKit

let APPLEGPU_DISASM_PY_PATH = Bundle.main.bundlePath + "/applegpu/disassemble.py"
let DEBUGGING = false;

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
if !DEBUGGING {
    try generate_binary_archive(path: gpu_bin_path)
}

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
if !DEBUGGING {
    try disasm(path: gpu_bin_path)
}

func run_pipeline(path: URL) throws {
    print("""

    -----------------------
    Running Render Pipeline
    -----------------------

    """)
    let lib = DEBUGGING ? device.makeDefaultLibrary()! : try! device.makeLibrary(URL: path)
    let pipelineDesc = create_pipeline_descriptor(lib: lib);
    let pipeline = try! device.makeRenderPipelineState(descriptor: pipelineDesc)
    
    
    let WIDTH = 4
    let HEIGHT = 4

    let writeToTextureBytes = device.makeBuffer(length: 4 /* 4 bytes per component */ * 4 /* 4 components (rgba) */ * WIDTH * HEIGHT, options: .storageModeShared)!
    
    let textureDesc = MTLTextureDescriptor()
    textureDesc.storageMode = .shared
    textureDesc.depth = 1
    textureDesc.pixelFormat = .rgba8Unorm
    textureDesc.usage = .renderTarget
    textureDesc.width = WIDTH
    textureDesc.height = HEIGHT
    let renderToTexture = device.makeTexture(descriptor: textureDesc)
    
    textureDesc.pixelFormat = .rgba32Float
    textureDesc.usage = .shaderWrite
    let writeToTexture = device.makeTexture(descriptor: textureDesc)!

    let captureManager = MTLCaptureManager.shared()
    let captureDescriptor = MTLCaptureDescriptor()
    captureDescriptor.captureObject = device
    
    if DEBUGGING {
        try! captureManager.startCapture(with: captureDescriptor)
    }
    
    let queue = device.makeCommandQueue()!
    let command = queue.makeCommandBuffer()!

    let renderDesc = MTLRenderPassDescriptor()
    let color = renderDesc.colorAttachments[0]!
    color.texture = renderToTexture
    color.loadAction = .clear
    color.storeAction = .store
    color.clearColor = MTLClearColorMake(0, 0, 0, 0)

    let r = command.makeRenderCommandEncoder(descriptor: renderDesc)!
    r.setRenderPipelineState(pipeline)
    r.setFragmentTexture(writeToTexture, index: 0)
    r.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    r.endEncoding()
    
    let b = command.makeBlitCommandEncoder()!
    b.copy(from: writeToTexture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOriginMake(0, 0, 0), sourceSize: MTLSizeMake(WIDTH, HEIGHT, 1), to: writeToTextureBytes, destinationOffset: 0, destinationBytesPerRow: 4 * 4 * WIDTH, destinationBytesPerImage: 4 * 4 * WIDTH * HEIGHT)
    b.endEncoding()
    command.commit()
    
    if DEBUGGING {
        captureManager.stopCapture()
    }
    command.waitUntilCompleted()
    
    func printVals(_ arr: Array<SIMD4<Float>>) {
        for y in 0..<HEIGHT {
            var r: [SIMD4<Float>] = []
            for x in 0..<WIDTH {
                r.append(arr[y * WIDTH + x]);
            }
            print(r)
        }
    }
    printVals(Array(writeToTextureBytes.contents().withMemoryRebound(to: SIMD4<Float>.self, capacity: WIDTH * HEIGHT) {
        UnsafeBufferPointer(start: $0, count: WIDTH * HEIGHT)
    }))
}
try run_pipeline(path: gpu_bin_path)

