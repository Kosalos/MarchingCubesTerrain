import UIKit

let XSIZE = Int(300)
let YSIZE:Int = XSIZE
let HOP:Float = Float(XSIZE) / Float(GSIZE)

class PanView: UIView {
    var context:CGContext?

    override func draw(_ rect: CGRect) {
        var idx = Int()
        var jIndex = Int()
        var xp = CGFloat()
        var zp = CGFloat()
        
        context = UIGraphicsGetCurrentContext()

        for x in 0 ..< GSIZE {
            xp = CGFloat(x) * CGFloat(HOP)
            
            for z in 0 ..< GSIZE {
                zp = CGFloat(GSIZE - 1 - z) * CGFloat(HOP)
                
                idx = x + cursor.y * GSY + z * GSZ
                
                jIndex = Int(Float(255) * grid[idx].flux / Float(MAX_FLUX))
                if jIndex > 255 { jIndex = 255 }
                let color = colorMap1[jIndex]
                
                UIColor(red:CGFloat(color.x), green:CGFloat(color.y), blue:CGFloat(color.z), alpha: 1).setFill()
                UIBezierPath(rect:CGRect(x:xp, y:zp, width:CGFloat(HOP+1), height:CGFloat(HOP+1))).fill()
            }
        }
        
        // cursor
        xp = CGFloat(cursor.x) * CGFloat(HOP)
        let yp = CGFloat(GSIZE - cursor.z) * CGFloat(HOP)
        context?.setLineWidth(2)
        context?.setStrokeColor(UIColor.black.cgColor)
        context?.move(to: CGPoint(x:xp, y:0)); context?.addLine(to: CGPoint(x:xp, y:bounds.size.height))
        context?.move(to: CGPoint(x:0, y:yp)); context?.addLine(to: CGPoint(x:bounds.size.width, y:yp))
        context?.strokePath()
    }
    
    // MARK: Touch --------------------------
    
    var panTouchDown = Bool(false)
    
    func updateCursor(_ rx:CGFloat, _ rz:CGFloat) {
        var x:Int = Int(CGFloat(GSIZE) * rx)
        var z:Int = GSIZE - Int(CGFloat(GSIZE) * rz)
    
        if x < 1 { x = 1} else if x >= GSIZE-1 { x = GSIZE-2 }
        if z < 1 { z = 1} else if z >= GSIZE-1 { z = GSIZE-2 }
    
        blob.updateCursorPosition(iVertex(x,cursor.y,z),panTouchDown)
        panTouchDown = true

        setNeedsDisplay()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            updateCursor(pt.x / CGFloat(XSIZE), pt.y / CGFloat(XSIZE))
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesBegan(touches, with: event)
        vc.metalViewL.draw()        
        if vc.isStereo { vc.metalViewR.draw() }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        panTouchDown = false;
    }
}

