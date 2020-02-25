/*
 * KDDragAndDropManager.swift
 * Created by Michael Michailidis on 10/04/2015.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 */

import UIKit

@objc public protocol KDDraggable {
    func canDragAtPoint(_ point : CGPoint) -> Bool
    func representationImageAtPoint(_ point : CGPoint) -> UIView?
    func dataItemAtPoint(_ point : CGPoint) -> AnyObject?
    func dragDataItem(_ item : AnyObject) -> Void
    
    /* optional */ func startDraggingAtPoint(_ point : CGPoint) -> Void
    /* optional */ func stopDragging() -> Void
}

extension KDDraggable {
    public func startDraggingAtPoint(_ point : CGPoint) -> Void {}
    public func stopDragging() -> Void {}
}


public protocol KDDroppable {
    func canDropAtRect(_ rect : CGRect) -> Bool
    func willMoveItem(_ item : AnyObject, inRect rect : CGRect) -> Void
    func didMoveItem(_ item : AnyObject, inRect rect : CGRect) -> Void
    func didMoveOutItem(_ item : AnyObject) -> Void
    func dropDataItem(_ item : AnyObject, atRect : CGRect) -> Void
    func draggingOriginOfCell() -> CGPoint?
}

@available(iOS 10.0, *)
@objcMembers public class KDDragAndDropManager: NSObject, UIGestureRecognizerDelegate {
    
    fileprivate var canvas : UIView = UIView()
    fileprivate var views : [UIView] = []
    fileprivate var longPressGestureRecogniser = UILongPressGestureRecognizer()
    
    @objc public var didBeginDragging: (() -> Void)?
    @objc public var didEndDragging: (() -> Void)?
    @objc public var didDropIntoRemoveView: (() -> Void)?
    @objc public var startedDraggingOverDropView: (() -> Void)?
    @objc public var stoppedDraggingOverDropView: (() -> Void)?
    
    struct Bundle {
        var offset : CGPoint = CGPoint.zero
        var sourceDraggableView : UIView
        var overDroppableView : UIView?
        var representationImageView : UIView
        var dataItem : AnyObject
    }
    var bundle : Bundle?
    
    var animator: UIViewPropertyAnimator = UIViewPropertyAnimator()
    
    var dropToDeleteView: UIView?
    
    public init(canvas : UIView, collectionViews : [UIView]) {
        
        super.init()
        
        self.canvas = canvas
        
        self.longPressGestureRecogniser.delegate = self
        self.longPressGestureRecogniser.minimumPressDuration = 0.45
        self.longPressGestureRecogniser.addTarget(self, action: #selector(KDDragAndDropManager.updateForLongPress(_:)))
        self.canvas.isMultipleTouchEnabled = false
        self.canvas.addGestureRecognizer(self.longPressGestureRecogniser)
        self.views = collectionViews
    }
    
    public init(canvas : UIView, collectionViews : [UIView], dropToDeleteView : UIView? = nil) {
        super.init()
        
        self.canvas = canvas
        self.dropToDeleteView = dropToDeleteView
        
        self.longPressGestureRecogniser.delegate = self
        self.longPressGestureRecogniser.minimumPressDuration = 0.45
        self.longPressGestureRecogniser.addTarget(self, action: #selector(KDDragAndDropManager.updateForLongPress(_:)))
        self.canvas.isMultipleTouchEnabled = false
        self.canvas.addGestureRecognizer(self.longPressGestureRecogniser)
        self.views = collectionViews
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        guard gestureRecognizer.state == .possible else { return false }
        
        for view in self.views where view is KDDraggable  {
            
            let draggable = view as! KDDraggable
            
            let touchPointInView = touch.location(in: view)
            
            guard draggable.canDragAtPoint(touchPointInView) == true else { continue }
            
            guard let representation = draggable.representationImageAtPoint(touchPointInView) else { continue }
            
            representation.frame = self.canvas.convert(representation.frame, from: view)
            
            let pointOnCanvas = touch.location(in: self.canvas)
            
            let offset = CGPoint(x: pointOnCanvas.x - representation.frame.origin.x, y: pointOnCanvas.y - representation.frame.origin.y)
            
            if let dataItem: AnyObject = draggable.dataItemAtPoint(touchPointInView) {
                
                self.bundle = Bundle(
                    offset: offset,
                    sourceDraggableView: view,
                    overDroppableView : view is KDDroppable ? view : nil,
                    representationImageView: representation,
                    dataItem : dataItem
                )
                
                return true
                
            }
            
        }
        
        return false
        
    }
    
    @objc public func updateForLongPress(_ recogniser : UILongPressGestureRecognizer) -> Void {
        
        guard let bundle = self.bundle else { return }
        
        let pointOnCanvas = recogniser.location(in: recogniser.view)
        let sourceDraggable : KDDraggable = bundle.sourceDraggableView as! KDDraggable
        let pointOnSourceDraggable = recogniser.location(in: bundle.sourceDraggableView)
        
        switch recogniser.state {
            
        case .began :
            self.canvas.addSubview(bundle.representationImageView)
            
            sourceDraggable.startDraggingAtPoint(pointOnSourceDraggable)
            self.didBeginDragging?()
            
            // TODO: Create a callback for getting frame for overlay
            let overlayView = UIView(frame: CGRect(x: 13, y: 14, width: 60, height: 60))
            overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            overlayView.layer.masksToBounds = true
            overlayView.layer.cornerRadius = 10
            bundle.representationImageView.addSubview(overlayView)
            
            UIView.animateKeyframes(withDuration: 0.3, delay: 0.0, options: .calculationModeCubic, animations: {
                
                UIView.animateKeyframes(withDuration: 0.15, delay: 0.0, animations: {
                    overlayView.alpha = 0.0
                }, completion: { (_) in
                    overlayView.removeFromSuperview()
                })
                
                UIView.animateKeyframes(withDuration: 0.15, delay: 0.15, animations: {
                    bundle.representationImageView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                    bundle.representationImageView.alpha = 0.7
                })
            })
            //        case .possible:
            //            print("touch stopped")
        //            fallthrough
        case .changed :
            
            // Update the frame of the representation image
            //            var repImgFrame = bundle.representationImageView.frame
            
            
            animator.addAnimations {
                bundle.representationImageView.center = pointOnCanvas
            }
            
            animator.startAnimation()
            
            var overlappingAreaMAX: CGFloat = 0.0
            
            var mainOverView: UIView?
            
            for view in self.views where view is KDDraggable  {
                
                let viewFrameOnCanvas = self.convertRectToCanvas(view.frame, fromView: view)
                
                
                /*                 ┌────────┐   ┌────────────┐
                 *                 │       ┌┼───│Intersection│
                 *                 │       ││   └────────────┘
                 *                 │   ▼───┘│
                 * ████████████████│████████│████████████████
                 * ████████████████└────────┘████████████████
                 * ██████████████████████████████████████████
                 */
                
                let overlappingAreaCurrent = bundle.representationImageView.frame.intersection(viewFrameOnCanvas).area
                
                if overlappingAreaCurrent > overlappingAreaMAX {
                    
                    overlappingAreaMAX = overlappingAreaCurrent
                    
                    mainOverView = view
                }
            }
            
            if let droppable = mainOverView as? KDDroppable {
                
                let rect = self.canvas.convert(bundle.representationImageView.frame, to: mainOverView)
                
                if droppable.canDropAtRect(rect) {
                    
                    // Send callbacks if we have added drop to delete view previously
                    if let dropView = dropToDeleteView {
                        if isCellInBoundsOf(dropView: dropView, bundle: bundle) {
                            self.startedDraggingOverDropView?()
                        } else {
                            self.stoppedDraggingOverDropView?()
                        }
                    }
                    
                    if mainOverView != bundle.overDroppableView { // if it is the first time we are entering
                        (bundle.overDroppableView as! KDDroppable).didMoveOutItem(bundle.dataItem)
                        droppable.willMoveItem(bundle.dataItem, inRect: rect)
                    }
                    
                    // set the view the dragged element is over
                    self.bundle!.overDroppableView = mainOverView
                    
                    droppable.didMoveItem(bundle.dataItem, inRect: rect)
                }
            }
            
        case .ended :
            
            if let dropView = dropToDeleteView {
                if isCellInBoundsOf(dropView: dropView, bundle: bundle) {
                    if let droppable = bundle.overDroppableView as? KDDroppable {
                        sourceDraggable.dragDataItem(bundle.dataItem)
                        let rect = self.canvas.convert(bundle.representationImageView.frame, to: bundle.overDroppableView)
                        droppable.dropDataItem(bundle.dataItem, atRect: rect)
                        bundle.representationImageView.removeFromSuperview()
                        sourceDraggable.stopDragging()
                        self.didDropIntoRemoveView?()
                        return
                        //self.didEndDragging?()
                    }
                }
            }
            
            if bundle.sourceDraggableView != bundle.overDroppableView { // if we are actually dropping over a new view.
                
                if let droppable = bundle.overDroppableView as? KDDroppable {
                    
                    sourceDraggable.dragDataItem(bundle.dataItem)
                    
                    let rect = self.canvas.convert(bundle.representationImageView.frame, to: bundle.overDroppableView)
                    
                    droppable.dropDataItem(bundle.dataItem, atRect: rect)
                    
                }
            }
            
            animator.stopAnimation(true)
            
            var destinationPoint: CGPoint = CGPoint.zero
            if let droppable = bundle.sourceDraggableView as? KDDroppable, let point = droppable.draggingOriginOfCell() {
                destinationPoint = self.canvas.convert(point, from: bundle.sourceDraggableView)
            }
            
            UIView.animate(withDuration: 0.1, animations: {
                bundle.representationImageView.transform = CGAffineTransform.identity
                bundle.representationImageView.alpha = 1.0
                if destinationPoint != CGPoint.zero {
                    bundle.representationImageView.frame.origin = destinationPoint
                }
            }) { (_) in
                bundle.representationImageView.removeFromSuperview()
                sourceDraggable.stopDragging()
                self.didEndDragging?()
            }
            
        default:
            break
            
        }
        
    }
    
    // MARK: Helper Methods
    func convertRectToCanvas(_ rect : CGRect, fromView view : UIView) -> CGRect {
        
        var r = rect
        var v = view
        
        while v != self.canvas {
            
            guard let sv = v.superview else { break; }
            
            r.origin.x += sv.frame.origin.x
            r.origin.y += sv.frame.origin.y
            
            v = sv
        }
        
        return r
    }
    
    private func isCellInBoundsOf(dropView: UIView, bundle: Bundle) -> Bool {
        // Check if representation image view is dropped/ragged in bounds of dropView
        let representationViewFrame = bundle.representationImageView.frame
        
        // Define proper bounds of the dropView
        let minX = dropView.frame.origin.x
        let minY = dropView.frame.origin.y
        let maxX = dropView.frame.size.width
        let maxY = dropView.frame.size.height
        
        // Define the center of the represetationView
        let representationCenterX = representationViewFrame.origin.x + representationViewFrame.size.width/2
        let representationCenterY = representationViewFrame.origin.y + representationViewFrame.size.height/2
        
        // Check if represetnationView center is within dropView bounds
        let isWithinXCoordinate = representationCenterX >= minX && representationViewFrame.origin.x <= maxX
        let isWithinYCoordinate = representationCenterY >= minY && representationViewFrame.origin.y <= maxY
        
        return isWithinXCoordinate && isWithinYCoordinate
    }
    
}


extension CGRect: Comparable {
    
    public var area: CGFloat {
        return self.size.width * self.size.height
    }
    
    public static func <=(lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.area <= rhs.area
    }
    public static func <(lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.area < rhs.area
    }
    public static func >(lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.area > rhs.area
    }
    public static func >=(lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.area >= rhs.area
    }
}

