//
//  Director.swift
//
//  Created by Andrey Volodin on 08.06.16.
//  Copyright © 2016. All rights reserved.
//

import Foundation
import SwiftMath

public class Director {
    internal static var stack = [Director?]()
    public static var current: Director! = nil

    public static func pushCurrentDirector(_ director: Director) {
        stack.append(current)
        self.current = director
    }

    public static func popCurrentDirector() {
        self.current = stack.removeLast()
    }

    // internal timer
    var oldFrameSkipInterval: Int = 1
    var frameSkipInterval: Int = 1
    /* stats */
    var displayStats: Bool = true
    var frames: Int = 0
    var totalFrames: Int = 0
    var secondsPerFrame: Time = 0.0
    var accumDt: Time = 0.0
    var frameRate: Time = 0.0
    /* is the running scene paused */
    var isPaused: Bool = false
    /* This object will be visited after the scene. Useful to hook a notification node */
    var notificationNode: Node?
    /* will be the next 'runningScene' in the next frame
     nextScene is a weak reference. */
    internal weak var nextScene: Scene?

    /* Whether or not the replaced scene will receive the cleanup message.
     If the new scene is pushed, then the old scene won't receive the "cleanup" message.
     If the new scene replaces the old one, the it will receive the "cleanup" message.
     */
    /* If YES, then "old" scene will receive the cleanup message */
    internal var sendCleanupToScene: Bool = false
    /* scheduled scenes */
    var scenesStack = [Scene]()
    /* last time the main loop was updated */
    var lastUpdate: Time = 0.0
    /* delta time since last tick to main loop */
    var dt: Time = 0.0
    /* whether or not the next delta time will be zero */
    var nextDeltaTimeZero: Bool = false
    /* renderer that draws scene on the screen */
    lazy var renderer: Renderer = BGFXRenderer()

    private(set) public var responderManager: ResponderManager!

    /// User definable value that is used for default contentSizes of many node types (Scene, NodeColor, etc).
    /// Defaults to the view size.
    public var designSize : Size {
        get {
            // Return the viewSize unless designSize has been set.
            return (_designSize == Size.zero ? self.viewSize : _designSize)
        }

        set {
            _designSize = newValue
        }
    }
    private var _designSize = Size.zero

    /** @name Working with View and Projection */
    /// View used by the director for rendering.
    public weak var view: DirectorView?

    /** The current running Scene. Director can only run one Scene at a time.
     @see presentScene: */
    internal(set) public var runningScene: Scene?

    /** Whether or not the Director is active (animating).
     @see paused
     @see startRunLoop
     @see stopRunLoop */
    internal(set) public var isAnimating: Bool = false

    public init(view: DirectorView) {
        self.view = view
        self.responderManager = ResponderManager(director: self)
    }

    public func purgeCachedData() {
        if Director.current.view != nil {
            TextureCache.shared.removeUnusedTextures()
        }
        FileLocator.shared.purgeCache()
    }

    public func convertToGL(_ uiPoint: Point) -> Point {
        var transform = runningScene!.projection
        let invTransform = transform.inversed
        // Calculate z=0 using -> transform*[0, 0, 0, 1]/w
        let zClip: Float = transform[3, 2] / transform[3, 3]
        let glSize: Size = viewSize
        var clipCoord = vec3(2.0 * Float(uiPoint.x / glSize.width) - 1.0, 2.0 * Float(uiPoint.y / glSize.height) - 1.0, zClip)
        clipCoord.y *= flipY
        return invTransform.multiplyAndProject(v: clipCoord).xy
    }

    public func convertToUI(_ glPoint: Point) -> Point {
        let transform = runningScene!.projection
        let clipCoord = transform.multiplyAndProject(v: vec3(glPoint))
        let glSize: Size = viewSize
        return glSize * p2d(clipCoord.x * 0.5 + 0.5, clipCoord.y * flipY * 0.5 + 0.5)
    }

    /** @returns The size of the view in points.
     @see viewSizeInPixels */
    public var viewSize: Size {
        return view!.size
    }

    /** @returns The size of the view in pixels.
     On Mac winSize and winSizeInPixels return the same value.
     @see viewSize
     */
    public var viewSizeInPixels: Size {
        return view!.sizeInPixels
    }

    /** Ends the execution, releases the running scene.
     It doesn't remove the view from the view hierarchy. You have to do it manually.
     */
    public func end() {
        runningScene!._onExitTransitionDidStart()
        runningScene!._onExit()
        runningScene!.cleanup()
        self.runningScene = nil
        self.nextScene = nil
        // remove all objects, but don't release it.
        // runWithScene might be executed after 'end'.
        scenesStack.removeAll()
        self.stopRunLoop()
        //self.delegate = nil
        // Purge all managers / caches
        SpriteFrame.purgeCache()
        TextureCache.shared.removeUnusedTextures()
        FileLocator.shared.purgeCache()
    }

    /** Pauses the running scene. All scheduled timers and actions will be paused.
     When paused, the director refreshes the screen at a very low framerate (4 fps) to conserve battery power.
     @see resume
     */
    public func pause() {
        if isPaused {
            return
        }

        self.oldFrameSkipInterval = frameSkipInterval
        // when paused, don't consume CPU
        self.frameSkipInterval = 15
        self.isPaused = true
    }

    /** Resumes the paused scene and its scheduled timers and actions.
     The "delta time" will be set to 0 as if the game wasn't paused.
     @see pause
     @see nextDeltaTimeZero
     */
    public func resume() {
        if !isPaused {
            return
        }

        self.frameSkipInterval = oldFrameSkipInterval
        self.lastUpdate = Time.absoluteTime
        self.isPaused = false
        self.dt = 0
    }
}
