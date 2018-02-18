import UIKit

struct iVertex {
    var x:Int
    var y:Int
    var z:Int
    
    init() { x = 0; y = 0; z = 0 }
    init(_ xx:Int, _ yy:Int, _ zz:Int) { x = xx; y = yy; z = zz }
}

let MODE_ADD:Int32 = 0
let MODE_SUB:Int32 = 1
let MODE_MOVE:Int32 = 2

extension Control {
    init() {
        mvp = float4x4()
        mode = MODE_ADD
        light = float3(10,10,0)
        tCount = 0
        ambient = 0.1 
        isoValue = 1.5
    }
}

extension TVertex {
    init(_ p:float3) {
        pos = p
        nrm = float3()
        txt = float2(0,0)
        flux = 0
        inside = 0
    }
}

extension Float {
    mutating func clamp(_ min:Float, _ max:Float) {
        if self < min { self = min }
        if self > max { self = max }
    }
}

let GSIZE:Int = Int(SGSIZE)     // grid dimension
let GTOTAL:Int = GSIZE * GSIZE * GSIZE
let MAX_TRI:Int = GTOTAL * 10

let GSX:Int = 1         // x,y,z indices into grid storage
let GSY:Int = GSIZE
let GSZ:Int = GSIZE * GSIZE
let MAX_FLUX:Float = 5

var control = Control()
var blob = Blob()
var heightView:HeightView! = nil
var panView:PanView! = nil

var cursor = iVertex()
var grid = Array(repeating:TVertex(), count:GTOTAL)  // storage of all cube nodes
var tri = Array(repeating:TVertex(), count:MAX_TRI)     // triangle mesh storage
var brushWidth:Float = 1

//MARK: -

class Blob {
    var vBuffer: MTLBuffer?
    var isDirty:Bool = false
    
    init() {
        vBuffer = gDevice?.makeBuffer(bytes:tri, length: MAX_TRI * MemoryLayout<TVertex>.size, options: MTLResourceOptions())!
        reset()
    }
    
    func updateIsoValue(_ ratio:Float) { control.isoValue = 1.1 - ratio }
    func alterIsoValue(_ dir:Float) { control.isoValue += dir * 0.0005 }
    
    //MARK: -
    
    func reset() {
        cursor.x = GSIZE / 2
        cursor.z = GSIZE / 2
        cursor.y = GSIZE / 2
    
        initializeNodeStorage()
        control.mode = MODE_ADD
        isDirty = true
    }
    
    func nodeIndex(_ x:Int, _ y:Int, _ z:Int) -> Int {
        let index = x + y * GSY + z * GSZ;
        if index < 0 { return 0 }
        if index >= GTOTAL-1 { return GTOTAL-1 }
        return index
    }
    
    func nodeIndex(_ position:iVertex) -> Int { return nodeIndex(position.x,position.y,position.z) }
    
    //MARK: -
    
    var oldGrid = Array(repeating:TVertex(), count:GTOTAL)

    func smoothPressed() {
        for i in 0 ..< GTOTAL { oldGrid[i] = grid[i] }
    
        for z in 1 ..< GSIZE-1 {
            for y in 1 ..< GSIZE-1 {
                for x in 1 ..< GSIZE-1 {
                    var total = Float()
    
                    // 3x3x3 grid of nodes surrounding current position
                    for zz in z-1 ... z+1 {
                        for yy in y-1 ... y+1 {
                            for xx in x-1 ... x+1 {
                                let index = nodeIndex(xx,yy,zz)
                                total += oldGrid[index].flux
                            }
                        }
                    }
                    
                    let index = nodeIndex(x,y,z)
                    total += oldGrid[index].flux * 8  // biased to current value
    
                    grid[index].flux = total / Float(27 + 8)
                    
                    if grid[index].flux < 0 {
                        grid[index].flux = 0
                    }
                    if grid[index].flux > MAX_FLUX {
                        grid[index].flux = MAX_FLUX
                    }
                }
            }
        }
        
        isDirty = true
    }
    
    //MARK: -
    
    func copyDownButtonPressed() {
        for x in 1 ..< GSIZE-1 {
            for z in 1 ..< GSIZE-1 {
                var highFlux = Float()
    
                for y in stride(from:GSIZE-1, to: 0, by: -1) {
                    let index = nodeIndex(x,y,z)
                    
                    if grid[index].flux > highFlux {
                        highFlux = grid[index].flux
                    }
                    else {
                        grid[index].flux = highFlux
                    }
                }
            }
        }
        
        isDirty = true
    }
    
//    func debug() {
//        let gg = Float(GSIZE)
//        for i in 0 ..< control.tCount {
//            let g = tri[Int(i)]
//            if fabs(g.pos.x) > gg || fabs(g.pos.y) > gg || fabs(g.pos.z) > gg {
//                let str = String(format:"%3d: Pos %7.3f, %7.3f, %7.3f   Flux: %7.3f", i,g.pos.x,g.pos.y,g.pos.z, g.flux)
//                Swift.print(str)
//            }
//        }
//    }
    
    func segmentSelect(_ index:Int) {
        let mm = [ MODE_ADD,MODE_SUB,MODE_MOVE ]
        control.mode = mm[index]
    }
    
    func initializeNodeStorage() {
        let gs = -Float(GSIZE/2)
        
        for z in 0 ..< GSIZE {
            for y in 0 ..< GSIZE {
                for x in 0 ..< GSIZE {
                    let index = nodeIndex(x,y,z)
                    grid[index].flux = 0
                    grid[index].pos.x = gs + Float(x)
                    grid[index].pos.y = gs + Float(y)
                    grid[index].pos.z = gs + Float(z)
                    grid[index].nrm = float3()
                }
            }
        }
    
        // ground plane
        for z in 1 ..< GSIZE-1 {
            for x in 1 ..< GSIZE-1 {
                let index = nodeIndex(x,1,z)
                grid[index].flux = 2
            }
        }

        updateInsideAndNormal()
    }
    
    //MARK: -
    
    func updateInsideAndNormal() {  computeShader.processGridInsideAndNormal(&grid)  }
    
    // jump cursor to specified position, or walk there node by node
    func updateCursorPosition(_ newPosition:iVertex, _ isDraggingFinger:Bool) {
        let FLUX_DELTA:Float = 1.5
        
        func affectNodeAndNeighbors(_ position:iVertex) {
            func affectNodeFlux(_ x:Int, _ y:Int, _ z:Int, _ deltaFlux:Float) {
                let index = nodeIndex(x,y,z)
                if control.mode == MODE_ADD { grid[index].flux += deltaFlux } else
                if control.mode == MODE_SUB { grid[index].flux -= deltaFlux }
                grid[index].flux.clamp(0, MAX_FLUX)
            }
            
            for x in 1 ..< GSIZE-1 {
                let dx = abs(position.x - x)
                if dx > 2 { continue }
                let xx = Float(dx * dx)

                for y in 1 ..< GSIZE-1 {
                    let dy = abs(position.y - y)
                    if dy > 2 { continue }
                    let yy = Float(dy * dy)

                    for z in 1 ..< GSIZE-1 {
                        let dz = abs(position.z - z)
                        if dz > 2 { continue }
                        let zz = Float(dz * dz)
                        
                        let distance:Float = sqrt(xx + yy + zz) * 3
                        if distance == 0 { continue }
                        
                        affectNodeFlux(x,y,z,brushWidth / distance);
                    }
                }
            }
        }
        
        if control.mode == MODE_MOVE {
            cursor = newPosition
        }
        else {
            if !isDraggingFinger {
                cursor = newPosition
                affectNodeAndNeighbors(cursor)
            }
            else {
                while true {
                    if (newPosition.x == cursor.x) && (newPosition.y == cursor.y) && (newPosition.z == cursor.z) { break }
                    if cursor.x != newPosition.x { cursor.x += (newPosition.x > cursor.x) ? 1 : -1 }
                    if cursor.y != newPosition.y { cursor.y += (newPosition.y > cursor.y) ? 1 : -1 }
                    if cursor.z != newPosition.z { cursor.z += (newPosition.z > cursor.z) ? 1 : -1 }
                    affectNodeAndNeighbors(cursor)
                }
            }
            
            isDirty = true
        }
    }
    
    func scrollTextures() {
        computeShader.processScrollTexture(&grid)
    }
    
    //MARK: -
    
    var sineData = Array(repeating:Float(), count:MAX_TRI)
    var sineAngle = Array(repeating:Float(), count:MAX_TRI)
    
    func initSkeletonData() {
        for i in 0 ..< GTOTAL {
            let v = Int(grid[i].flux * 100.0)

            sineData[i] = ((v % 3) == 0) ? grid[i].flux : 0
            if sineData[i] > 0 {  sineAngle[i] = sinf(grid[i].flux * 10) }
        }
    }

    func skeletonChange() {
        for z in 1 ..< GSIZE-1 {
            for y in 1 ..< GSIZE-1 {
                for x in 1 ..< GSIZE-1 {
                    let index = nodeIndex(x,y,z)
                    if sineData[index] == 0 { continue }

                    grid[index].flux = sineData[index] + sineData[index] * sinf(sineAngle[index]) * 10
                    grid[index].flux.clamp(0, MAX_FLUX)
                    sineAngle[index] += 0.1
                }
            }
        }

        isDirty = true
    }

    //MARK: -

    func randomFluxChange() {
        for z in 1 ..< GSIZE-1 {
            for y in 0 ..< GSIZE {
                for x in 1 ..< GSIZE-1 {
                    let index = nodeIndex(x,y,z)
                    
                    if grid[index].flux == 0 { continue }
                    if (Int(arc4random()) & 31) > 3 { continue }
    
                    grid[index].flux += (Int(arc4random()) & 1) == 1 ? +0.01 : -0.01
                    grid[index].flux.clamp(0, MAX_FLUX)
                }
            }
        }

        isDirty = true
    }
    
    //MARK: -
    
    func calcMarchingCubes() {
        func addTriangleToList(_ v1:TVertex, _ v2:TVertex, _ v3:TVertex) {
            func calculateNormal( _ v1:float3, _ v2:float3, _ v3:float3) -> float3 {
                var d1 = float3()
                var d2 = float3()
                
                d1.x = (v2.x - v1.x) // crossproduct
                d1.y = (v2.y - v1.y)
                d1.z = (v2.z - v1.z)
                d2.x = (v3.x - v1.x)
                d2.y = (v3.y - v1.y)
                d2.z = (v3.z - v1.z)
                
                var ans = float3()
                ans.x = d1.y * d2.z - d1.z * d2.y
                ans.y = d1.z * d2.x - d1.x * d2.z
                ans.z = d1.x * d2.y - d1.y * d2.x
                return normalize(ans)
            }
            
            let nrm = calculateNormal(v1.pos,v2.pos,v3.pos)
            
            func addVertex(_ v:TVertex) {
                let KK = Float(0.03)
                let index = Int(control.tCount)
                control.tCount += 1

                tri[index] = v
                tri[index].nrm = nrm
                tri[index].txt.x = v.nrm.x + v.pos.y * KK
                tri[index].txt.y = v.nrm.z + v.pos.y * KK
            }
            
            addVertex(v1)
            addVertex(v2)
            addVertex(v3)
        }
        
        func interpolate(_ gridIndex1:Int, _ gridIndex2:Int) -> TVertex {
            let v1 = grid[gridIndex1]
            let v2 = grid[gridIndex2]
            
            if (v1.flux <= control.isoValue && v2.flux <= control.isoValue) ||  // shouldn't be here
               (v1.flux >= control.isoValue && v2.flux >= control.isoValue) {
                return v1
            }
            
            let den:Float = v2.flux - v1.flux
            if den == 0 { return v1 }
            let ratio:Float = (control.isoValue - v1.flux) / den
            
            func mix(_ v1:Float, _ v2:Float) -> Float { return v1 + (v2 - v1) * ratio }
            
            var answer = TVertex()
            answer.flux =  mix(v1.flux,v2.flux)
            answer.pos.x = mix(v1.pos.x,v2.pos.x)
            answer.pos.y = mix(v1.pos.y,v2.pos.y)
            answer.pos.z = mix(v1.pos.z,v2.pos.z)
            answer.nrm.x = mix(v1.nrm.x,v2.nrm.x)
            answer.nrm.y = mix(v1.nrm.y,v2.nrm.y)
            answer.nrm.z = mix(v1.nrm.z,v2.nrm.z)
            return answer
        }
        
        control.tCount = 0

        var lookup = Int()
        var verts = Array(repeating:TVertex(), count:12)

        for z in 0 ..< GSIZE - 1 {
            for y in 0 ..< GSIZE - 1 {
                for x in 0 ..< GSIZE - 1 {
                    let idx = nodeIndex(x,y,z)
                    
                    lookup = 0
                    if grid[idx       + GSY + GSZ ].inside != 0 { lookup += 1 }
                    if grid[idx + GSX + GSY + GSZ ].inside != 0 { lookup += 2 }
                    if grid[idx + GSX + GSY       ].inside != 0 { lookup += 4 }
                    if grid[idx       + GSY       ].inside != 0 { lookup += 8 }
                    if grid[idx + GSZ ].inside != 0 { lookup += 16 }
                    if grid[idx + GSX + GSZ ].inside != 0 { lookup += 32 }
                    if grid[idx + GSX             ].inside != 0 { lookup += 64 }
                    if grid[idx                   ].inside != 0 { lookup += 128 }
    
                    if lookup > 0 && lookup < 255 {
                        let et:UInt16 = edgeTable[lookup]
                        if (et &  1) != 0   { verts[ 0] = interpolate(idx       + GSY + GSZ , idx + GSX + GSY + GSZ )}
                        if (et &  2) != 0   { verts[ 1] = interpolate(idx + GSX + GSY + GSZ , idx + GSX + GSY       )}
                        if (et &  4) != 0   { verts[ 2] = interpolate(idx + GSX + GSY       , idx       + GSY       )}
                        if (et &  8) != 0   { verts[ 3] = interpolate(idx       + GSY       , idx       + GSY + GSZ )}
                        if (et & 16) != 0   { verts[ 4] = interpolate(idx             + GSZ , idx + GSX       + GSZ )}
                        if (et & 32) != 0   { verts[ 5] = interpolate(idx + GSX       + GSZ , idx + GSX             )}
                        if (et & 64) != 0   { verts[ 6] = interpolate(idx + GSX             , idx                   )}
                        if (et & 128) != 0  { verts[ 7] = interpolate(idx                   , idx             + GSZ )}
                        if (et & 256) != 0  { verts[ 8] = interpolate(idx       + GSY + GSZ , idx             + GSZ )}
                        if (et & 512) != 0  { verts[ 9] = interpolate(idx + GSX + GSY + GSZ , idx + GSX       + GSZ )}
                        if (et & 1024) != 0 { verts[10] = interpolate(idx + GSX + GSY       , idx + GSX             )}
                        if (et & 2048) != 0 { verts[11] = interpolate(idx       + GSY       , idx                   )}
    
                        var i:Int = 0
                        while true {
                            if triTable[lookup][i] > 11 { break }
                            addTriangleToList(verts[Int(triTable[lookup][i  ])],
                                              verts[Int(triTable[lookup][i+1])],
                                              verts[Int(triTable[lookup][i+2])])
                            i += 3
                            if control.tCount > MAX_TRI - 4 { return }
                        }
                    }
                }
            }
        }
    }
    
    func render(_ renderEncoder:MTLRenderCommandEncoder) {
        if vBuffer == nil { return }

        if isDirty {
            updateInsideAndNormal()
            calcMarchingCubes()
            if control.tCount > 0 { isDirty = false }
        }
        
        if control.tCount > 0 {
            vBuffer?.contents().copyBytes(from: tri, count:Int(control.tCount) * MemoryLayout<TVertex>.stride)
            renderEncoder.setVertexBuffer(vBuffer, offset: 0, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount:Int(control.tCount))
        }
    }

}

