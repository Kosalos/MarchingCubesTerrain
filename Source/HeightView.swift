import UIKit

class HeightView: UIView {
    var context:CGContext?
    let HOP = CGFloat(XSIZE) / CGFloat(GSIZE)
    
    override func draw(_ rect: CGRect) {
        context = UIGraphicsGetCurrentContext()
        var yp = CGFloat()
        
        for y in 0 ..< GSIZE {
            yp = CGFloat(YSIZE-1) - CGFloat(y) * HOP
            drawLine(yp, y == cursor.y ? UIColor.yellow : UIColor.lightGray )
        }
    }
    
    func drawLine(_ y:CGFloat, _ color:UIColor) {
        context!.setStrokeColor(color.cgColor)
        context!.setLineWidth(3)
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x:0, y:y))
        path.addLine(to: CGPoint(x:100, y:y))
        context!.addPath(path.cgPath)
        context!.strokePath()
    }

    func refresh() { setNeedsDisplay() }
    
    func updateCursor(_ y:Int) {
        var c = cursor
        c.y = y
        if c.y < 1 { c.y = 1 } else if c.y > GSIZE-1 { c.y = GSIZE-1 }
    
        blob.updateCursorPosition(c,true)
        
        setNeedsDisplay()
        vc.panView.setNeedsDisplay()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let pt = touch.location(in: self)
            updateCursor(GSIZE - 1 - Int( CGFloat(GSIZE) * pt.y / bounds.size.height))
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesBegan(touches, with: event)
    }
}

