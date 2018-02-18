import Foundation
import Metal
import simd

let computeShader = ComputeShader()

class ComputeShader {
    let commandQueue: MTLCommandQueue
    let gLength = GTOTAL * MemoryLayout.stride(ofValue: TVertex())
    let cLength = MemoryLayout.stride(ofValue:control)
    let vLength = 12 * MemoryLayout.stride(ofValue: TVertex())
    
    init() {
        self.commandQueue = gDevice.makeCommandQueue()!
    }
    
    func buildPipeline(_ shaderFunction:String) -> MTLComputePipelineState {
        var result:MTLComputePipelineState!
        
        do {
            let defaultLibrary = gDevice?.makeDefaultLibrary()
            let prg = defaultLibrary?.makeFunction(name:shaderFunction)
            result = try gDevice?.makeComputePipelineState(function: prg!)
        } catch { fatalError("Failed to setup " + shaderFunction) }
        
        return result
    }

    //MARK: -
    
    var pipe1:MTLComputePipelineState!

    func processGridInsideAndNormal(_ grid:inout [TVertex]) {
        let commandBuffer = commandQueue.makeCommandBuffer()
        let encoder = commandBuffer!.makeComputeCommandEncoder()

        let gBuffer  = gDevice?.makeBuffer(bytes: grid, length: gLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &control, length: cLength, options: [])
        
        let threadsPerGroup = MTLSize(width:32,height:1,depth:1)
        let numThreadgroups = MTLSize(width:(GTOTAL + 31)/32, height:1, depth:1)
        
        if pipe1 == nil { pipe1 = buildPipeline("calcGridInsideAndNormal") }
        
        encoder!.setComputePipelineState(pipe1!)
        encoder!.setBuffer(gBuffer,  offset: 0, index: 0)
        encoder!.setBuffer(cBuffer,  offset: 0, index: 1)
        encoder!.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder!.endEncoding()
        
        commandBuffer!.commit()
        commandBuffer!.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: gLength, freeWhenDone: false)
        data.getBytes(&grid, length:gLength)
    }

    //MARK: -
    var pipe2:MTLComputePipelineState!
    
    func processScrollTexture(_ grid:inout [TVertex]) {
        let commandBuffer = commandQueue.makeCommandBuffer()
        let encoder = commandBuffer!.makeComputeCommandEncoder()
        let tLength = Int(control.tCount) * MemoryLayout.stride(ofValue: TVertex())
        
        let gBuffer  = gDevice?.makeBuffer(bytes: &tri, length: tLength, options: [])
        let cBuffer = gDevice?.makeBuffer(bytes: &control, length: cLength, options: [])

        let threadsPerGroup = MTLSize(width:32,height:1,depth:1)
        let numThreadgroups = MTLSize(width:(GTOTAL + 31)/32, height:1, depth:1)
        
        if pipe2 == nil { pipe2 = buildPipeline("calcScrollTexture") }
        
        encoder!.setComputePipelineState(pipe2!)
        encoder!.setBuffer(gBuffer,  offset: 0, index: 0)
        encoder!.setBuffer(cBuffer,  offset: 0, index: 1)
        encoder!.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        encoder!.endEncoding()
        
        commandBuffer!.commit()
        commandBuffer!.waitUntilCompleted()
        
        let data = NSData(bytesNoCopy: gBuffer!.contents(), length: tLength, freeWhenDone: false)
        data.getBytes(&tri, length:gLength)
    }
}
