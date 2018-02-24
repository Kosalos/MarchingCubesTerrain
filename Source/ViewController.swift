import UIKit
import MetalKit

var paceRotate = CGPoint()
var timer = Timer()
var pencilStyle:Bool = false
var connectStyle:Bool = false
var vc:ViewController!

// used during development of rotated() layout routine to simulate other iPad sizes
//let scrnSz:[CGPoint] = [ CGPoint(x:768,y:1024), CGPoint(x:834,y:1112), CGPoint(x:1024,y:1366) ] // portrait 9.7, 10.5, 12.9" iPads
//let scrnIndex = 2
//let scrnLandscape:Bool = false

class ViewController: UIViewController{
    var pipeline1: MTLComputePipelineState!
    let queue = DispatchQueue(label: "Queue")
    lazy var device: MTLDevice! = MTLCreateSystemDefaultDevice()
    lazy var commandQueue: MTLCommandQueue! = { return self.device.makeCommandQueue() }()
    
    var rendererL: Renderer!
    var rendererR: Renderer!
    var isRandomFlux = Bool(false)
    var isSkeletonFlux = Bool(false)
    var isTextureScroll = Bool(false)
    var isStereo  = Bool(true)
    
    @IBOutlet var metalViewL: MTKView!
    @IBOutlet var metalViewR: MTKView!
    @IBOutlet var panView: PanView!
    @IBOutlet var heightView: HeightView!
    
    @IBOutlet var pencilButton: UIButton!
    @IBOutlet var connectButton: UIButton!
    @IBOutlet var resetButton: UIButton!
    @IBOutlet var stereoButton: UIButton!
    @IBOutlet var smoothButton: UIButton!
    @IBOutlet var copyDownButton: UIButton!
    @IBOutlet var randomFluxButton: UIButton!
    @IBOutlet var skeletonFluxButton: UIButton!
    @IBOutlet var scrollSkinButton: UIButton!
    @IBOutlet var changeSkinButton: UIButton!
    @IBOutlet var helpButton: UIButton!
    @IBOutlet var modeChangeSelector: UISegmentedControl!
    
    @IBOutlet var sIsoValue: SliderView!
    @IBOutlet var sBrushWidth: SliderView!
    @IBOutlet var sAmbient: SliderView!
    
    //MARK: -

    let bColors:[UIColor] = [
        UIColor(red:0.5, green:0.5, blue:0.5, alpha:1),
        UIColor(red:0.8, green:0.4, blue:0.0, alpha:1),
        ]

    @IBAction func pencilButtonPressed(_ sender: UIButton) {
        pencilStyle = !pencilStyle
        let colorIndex:Int = pencilStyle ? 1 : 0
        sender.backgroundColor = bColors[colorIndex]
    }
    
    @IBAction func connectButtonPressed(_ sender: UIButton) {
        connectStyle = !connectStyle
        let colorIndex:Int = connectStyle ? 1 : 0
        sender.backgroundColor = bColors[colorIndex]
    }
    
    @IBAction func smoothButtonPressed(_ sender: UIButton) {
        blob.smoothPressed()
        panView.setNeedsDisplay()
    }
    
    @IBAction func copyDownButtonPressed(_ sender: UIButton) {
        blob.copyDownButtonPressed()
        panView.setNeedsDisplay()
    }
    
    @IBAction func resetButtonPressed(_ sender: UIButton) {
        translation = float3(-0.75, 4.4375, 36.0627)
        arcBall.reset()
        blob.reset()
        modeChangeSelector.selectedSegmentIndex = 0
        panView.setNeedsDisplay()
        heightView.setNeedsDisplay()
    }
    
    @IBAction func stereoButtonPressed(_ sender: UIButton) {
        isStereo = !isStereo
        metalViewR.isHidden = !isStereo
        screenRotated()
    }
    
    @IBAction func randomFluxButtonPressed(_ sender: UIButton) { isRandomFlux = true }
    @IBAction func randomFluxButtonReleased(_ sender: UIButton) { isRandomFlux = false }
    @IBAction func scrollSkinButtonPressed(_ sender: UIButton) { isTextureScroll = !isTextureScroll }
    @IBAction func modeChanged(_ sender: UISegmentedControl) { blob.segmentSelect(sender.selectedSegmentIndex) }
    
    @IBAction func changeSkinButtonPressed(_ sender: UIButton) {
        rendererL.loadNextTexture()
        rendererR.loadNextTexture()
    }

    @IBAction func skeletonFluxButtonPressed(_ sender: UIButton) {
        isSkeletonFlux = true
        blob.initSkeletonData()
    }
    @IBAction func skeletonFluxButtonReleased(_ sender: UIButton) { isSkeletonFlux = false }
    
    //MARK: -
    
    override func viewDidLoad() {
        super.viewDidLoad()
        vc = self
        
        metalViewL.device = device
        metalViewL.backgroundColor = UIColor.clear
        metalViewR.device = device
        metalViewR.backgroundColor = UIColor.clear

        guard let newRenderer = Renderer(metalKitView: metalViewL, 0) else { print("Renderer cannot be initialized"); exit(0) }
        rendererL = newRenderer
        rendererL.mtkView(metalViewL, drawableSizeWillChange: metalViewL.drawableSize)
        metalViewL.delegate = rendererL

        guard let newRenderer2 = Renderer(metalKitView: metalViewR, 1) else { print("Renderer cannot be initialized"); exit(0) }
        rendererR = newRenderer2
        rendererR.mtkView(metalViewR, drawableSizeWillChange: metalViewR.drawableSize)
        metalViewR.delegate = rendererR

        timer = Timer.scheduledTimer(timeInterval: 1.0/20.0, target:self, selector: #selector(timerHandler), userInfo: nil, repeats:true)
        screenRotated()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        sBrushWidth.initializeFloat(&brushWidth, .direct, 0.2,2, 3, "Width")
        sIsoValue.initializeFloat(&control.isoValue, .delta, 0.01, 2.0, 1, "Iso")
        sAmbient.initializeFloat(&control.ambient, .direct, 0, 1, 1, "Ambient")
        
        resetButtonPressed(resetButton)
    }
    
    //MARK: -
    
    @objc func timerHandler() {
        _ = sBrushWidth.update()
        
        if sIsoValue.update() {
            blob.isDirty = true
        }
        
        if isRandomFlux {
            blob.randomFluxChange()
            panView.setNeedsDisplay()
        }
        
        if isSkeletonFlux {
            blob.skeletonChange()
            panView.setNeedsDisplay()
        }
        
        if isTextureScroll {
            blob.scrollTextures()
        }
        
        rotate(paceRotate.x,paceRotate.y)
    }
    
    //MARK:-
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { _ in
            self.screenRotated()
        }
    }
    
    @objc func screenRotated() {
        let xs:CGFloat = view.bounds.width
        let ys:CGFloat = view.bounds.height
//        let xs = scrnLandscape ? scrnSz[scrnIndex].y : scrnSz[scrnIndex].x
//        let ys = scrnLandscape ? scrnSz[scrnIndex].x : scrnSz[scrnIndex].y
        
        let cxs:CGFloat = 170   // slider width
        let bys:CGFloat = 35    // slider height
        let fullWidth:CGFloat = 720
        let fullHeight:CGFloat = 290
        let left:CGFloat = (xs - fullWidth)/2

        var ixs = (xs - 4) / 2
        if ixs + fullHeight > ys { ixs = ys - fullHeight - 4 }
        let iys = ixs

        if isStereo {
            metalViewL.frame = CGRect(x:xs/2 - ixs - 2, y:0, width:ixs, height:ixs)
            metalViewR.frame = CGRect(x:xs/2 + 2, y:0, width:ixs, height:iys)
        }
        else {
            ixs = xs - 4
            metalViewL.frame = CGRect(x:2, y:0, width:ixs, height:iys)
        }
        
        let by:CGFloat = iys + 10  // widget top
        var y:CGFloat = by
        var x:CGFloat = left
        let yhop:CGFloat = bys + 5
        let fw:CGFloat = 120
        
        func frame(_ xs:CGFloat, _ ys:CGFloat, _ dx:CGFloat, _ dy:CGFloat) -> CGRect {
            let r = CGRect(x:x, y:y, width:xs, height:ys)
            x += dx; y += dy
            return r
        }
        
        resetButton.frame = frame(fw,bys,0,yhop)
        smoothButton.frame = frame(fw,bys,0,yhop)
        copyDownButton.frame = frame(fw,bys,0,yhop)
        changeSkinButton.frame = frame(fw,bys,0,yhop)
        scrollSkinButton.frame = frame(fw,bys,0,yhop)
        randomFluxButton.frame = frame(fw,bys,0,yhop)
        skeletonFluxButton.frame = frame(fw,bys,0,0)
        x += fw + 20
        y = by
        sIsoValue.frame = frame(cxs,bys,0,bys+20)
        let x2 = x
        sBrushWidth.frame = frame(cxs,bys,cxs+5,0)
        pencilButton.frame = frame(bys,bys,0,bys+20)
        x = x2
        sAmbient.frame = frame(cxs,bys,0,bys+20)
        let x3 = x
        modeChangeSelector.frame = frame(cxs,bys,cxs+5,0)
        connectButton.frame = frame(bys,bys,0,bys+40)
        x = x3
        stereoButton.frame = frame(cxs/2,bys,cxs/2+25,0)
        helpButton.frame = frame(cxs/2,bys,0,0)
        x += cxs/2 + 25
        y = by
        let pv = fullHeight - 20
        heightView.frame = frame(70,pv,85,0)
        panView.frame = frame(pv,pv,0,0)
    }

    override var prefersStatusBarHidden: Bool { return true }
    
    //MARK: -

    func rotate(_ x:CGFloat, _ y:CGFloat) {
        let center:CGFloat = 300    // 0.5 x nib image size
        arcBall.mouseDown(CGPoint(x: center, y: center))
        arcBall.mouseMove(CGPoint(x: center - x, y: center - y))
    }
    
    func parseTranslation(_ pt:CGPoint) {
        let scale:Float = 0.05
        translation.x = Float(pt.x) * scale
        translation.y = -Float(pt.y) * scale
    }
    
    func parseRotation(_ pt:CGPoint) {
        let scale:CGFloat = 0.05
        paceRotate.x = pt.x * scale
        paceRotate.y = pt.y * scale
    }
    
    var numberPanTouches:Int = 0
    
    @IBAction func panGesture(_ sender: UIPanGestureRecognizer) {
        let pt = sender.translation(in: self.view)
        let count = sender.numberOfTouches
        if count == 0 { numberPanTouches = 0 }  else if count > numberPanTouches { numberPanTouches = count }
        
        switch sender.numberOfTouches {
        case 1 : if numberPanTouches < 2 { parseRotation(pt) } // prevent rotation after releasing translation
        case 2 : parseTranslation(pt)
        default : break
        }
    }

    @IBAction func pinchGesture(_ sender: UIPinchGestureRecognizer) {
        let min:Float = 1
        let max:Float = 100
        translation.z *= Float(1 + (1 - sender.scale) / 10 )
        if translation.z < min { translation.z = min }
        if translation.z > max { translation.z = max }
    }
    
    @IBAction func tapGesture(_ sender: UITapGestureRecognizer) {
        paceRotate.x = 0
        paceRotate.y = 0
    }
}

//MARK: -

func fClamp(_ v:Float, _ range:float2) -> Float {
    if v < range.x { return range.x }
    if v > range.y { return range.y }
    return v
}

func fClamp(_ v:Float, _ min:Float, _ max:Float) -> Float {
    if v < min { return min }
    if v > max { return max }
    return v
}


