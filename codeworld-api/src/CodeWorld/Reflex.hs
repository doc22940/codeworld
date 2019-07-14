{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecursiveDo #-}

{-
  Copyright 2019 The CodeWorld Authors. All rights reserved.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
-}

-- | Module for using CodeWorld pictures in Reflex-based FRP applications.
module CodeWorld.Reflex (
    -- $intro
    -- * Old Entry Point
    -- $old
      reflexOf
    , ReactiveInput
    , keyPress
    , keyRelease
    , textEntry
    , pointerPress
    , pointerRelease
    , pointerPosition
    , pointerDown
    , timePassing
    -- * New Entry Point
    -- $new
    , reactiveOf
    , debugReactiveOf
    , ReflexCodeWorld
    , getKeyPress
    , getKeyRelease
    , getTextEntry
    , getPointerClick
    , getPointerPosition
    , isPointerDown
    , getTimePassing
    , draw
    -- * Pictures
    , Picture
    , blank
    , polyline
    , thickPolyline
    , polygon
    , thickPolygon
    , solidPolygon
    , curve
    , thickCurve
    , closedCurve
    , thickClosedCurve
    , solidClosedCurve
    , rectangle
    , solidRectangle
    , thickRectangle
    , circle
    , solidCircle
    , thickCircle
    , arc
    , sector
    , thickArc
    , lettering
    , TextStyle(..)
    , Font(..)
    , styledLettering
    , colored
    , coloured
    , translated
    , scaled
    , dilated
    , rotated
    , pictures
    , (<>)
    , (&)
    , coordinatePlane
    , codeWorldLogo
    , Point
    , translatedPoint
    , rotatedPoint
    , scaledPoint
    , dilatedPoint
    , Vector
    , vectorLength
    , vectorDirection
    , vectorSum
    , vectorDifference
    , scaledVector
    , rotatedVector
    , dotProduct
    -- * Colors
    , Color(..)
    , Colour
    , pattern RGB
    , pattern HSL
    , black
    , white
    , red
    , green
    , blue
    , yellow
    , orange
    , brown
    , pink
    , purple
    , gray
    , grey
    , mixed
    , lighter
    , light
    , darker
    , dark
    , brighter
    , bright
    , duller
    , dull
    , translucent
    , assortedColors
    , hue
    , saturation
    , luminosity
    , alpha
    ) where

import CodeWorld.Driver
import CodeWorld.Picture
import CodeWorld.Color
import Control.Monad.Fix
import Control.Monad.Trans
import Data.Bool
import qualified Data.Text as T
import Reflex

-- $intro
-- = Using Reflex with CodeWorld
--
-- This is an alternative to the standard CodeWorld API, which is based on
-- the Reflex library.  You should import this *instead* of 'CodeWorld', since
-- the 'CodeWorld' module exports conflict with Reflex names.
--
-- You'll provide a function whose input can be used to access the user's
-- actions with keys, the mouse pointer, and time, and whose output is a
-- 'Picture'.  The 'Picture' value is build with the same combinators as the
-- main 'CodeWorld' library.
--
-- The Reflex API is documented in many places, but a great reference is
-- available in the <https://github.com/reflex-frp/reflex/blob/develop/Quickref.md
-- Reflex Quick Reference>.

-- $old
--
-- The old API consists of the function `reflexOf`.  WARNING: This API will soon
-- be deleted in favor of the newer API described below.
--
-- A simple example:
--
-- @
--     import CodeWorld.Reflex
--     import Reflex
--
--     main :: IO ()
--     main = reflexOf $ \\input -> do
--         angle <- foldDyn (+) 0 (gate (current (pointerDown input)) (timePassing input))
--         return $ (uncurry translated \<$> pointerPosition input \<*>)
--                $ (colored \<$> bool red green \<$> pointerDown input \<*>)
--                $ (rotated \<$> angle \<*>)
--                $ constDyn (solidRectangle 2 2)
-- @


-- | The entry point for running Reflex-based CodeWorld programs.
reflexOf
    :: (forall t m. (Reflex t, MonadHold t m, MonadFix m, PerformEvent t m,
                     MonadIO (Performable m), Adjustable t m, PostBuild t m)
        => ReactiveInput t -> m (Dynamic t Picture))
    -> IO ()
reflexOf program = runReactive $ \input -> do
    pic <- program input
    return (pic, pic)

{-# WARNING reflexOf
        ["Please use reactiveOf instead of reflexOf.",
         "reflexOf will be removed and replaced soon."] #-}

reactiveOf :: (forall t m. ReflexCodeWorld t m => m ()) -> IO ()
reactiveOf program = runReactive $ \input -> runReactiveProgram program input

{-# WARNING reactiveOf
        ["After the current migration is complete,",
         "reactiveOf will probably be renamed to reflexOf."] #-}

debugReactiveOf :: (forall t m. ReflexCodeWorld t m => m ()) -> IO ()
debugReactiveOf program = runReactive $ \input -> flip runReactiveProgram input $ do
    hoverAlpha <- getHoverAlpha
    rec
        resetClick <- resetButton hoverAlpha (9, -3) ((/= 1) <$> zoomFactor)
        zoomFactor <- zoomControls hoverAlpha (9, -6) resetClick
    transformUserPicture $ dilated <$> zoomFactor
    withZoomedMouseEvents zoomFactor $ program

{-# WARNING debugReactiveOf
        ["After the current migration is complete,",
         "debugReactiveOf will probably be renamed to debugReflexOf."] #-}

getHoverAlpha :: forall t m. ReflexCodeWorld t m => m (Dynamic t Double)
getHoverAlpha = do
    time <- getTimePassing
    move <- updated <$> getPointerPosition
    rec timeSinceMove <- foldDyn ($) 999 $ mergeWith (.) [
            (+) <$> gateDyn ((< 5) <$> timeSinceMove) time,
            const 0 <$ move
            ]
    return (alphaFromTime <$> timeSinceMove)
  where
    alphaFromTime t | t < 4.5   = 1
                    | t > 5.0   = 0
                    | otherwise = 10 - 2 * t

withZoomedMouseEvents :: Reflex t => Dynamic t Double -> ReactiveProgram t m a -> ReactiveProgram t m a
withZoomedMouseEvents zoomFactor = withReactiveInput $ \i -> i {
    pointerPress = attachPromptlyDynWith zoomPoint zoomFactor (pointerPress i),
    pointerRelease = attachPromptlyDynWith zoomPoint zoomFactor (pointerRelease i),
    pointerPosition = zoomPoint <$> zoomFactor <*> pointerPosition i
    }
  where zoomPoint z (x, y) = (x / z, y / z)

resetButton
    :: (PerformEvent t m, Adjustable t m, MonadIO (Performable m),
        PostBuild t m, MonadHold t m, MonadFix m)
    => Dynamic t Double
    -> Point
    -> Dynamic t Bool
    -> ReactiveProgram t m (Event t ())
resetButton hoverAlpha pos needsReset = do
    click <- gateDyn needsReset . ffilter (onRect 0.8 0.8 pos) <$> getPointerClick
    systemDraw $ uncurry translated pos <$> (bool (constDyn blank) (button <$> hoverAlpha) =<< needsReset)
    return $ () <$ click
  where
    button a =
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.7 0.2) <>
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.2 0.7) <>
        colored (RGBA 0.0 0.0 0.0 a) (thickRectangle 0.1 0.5 0.5) <>
        colored (RGBA 0.2 0.2 0.2 a) (rectangle 0.8 0.8) <>
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.8 0.8)

zoomControls
    :: (PerformEvent t m, Adjustable t m, MonadIO (Performable m),
        PostBuild t m, MonadHold t m, MonadFix m)
    => Dynamic t Double
    -> Point
    -> Event t ()
    -> ReactiveProgram t m (Dynamic t Double)
zoomControls hoverAlpha (x, y) resetClick = do
    zoomInClick <- zoomInButton hoverAlpha (x, y + 2)
    zoomOutClick <- zoomOutButton hoverAlpha (x, y - 2)
    rec
        zoomDrag <- zoomSlider hoverAlpha (x, y) zoomFactor
        zoomFactor <- foldDyn ($) 1 $ mergeWith (.) [
            (* zoomIncrement) <$ zoomInClick,
            (/ zoomIncrement) <$ zoomOutClick,
            const <$> zoomDrag,
            const 1 <$ resetClick
            ]
    return zoomFactor

zoomInButton
    :: (PerformEvent t m, Adjustable t m, MonadIO (Performable m),
        PostBuild t m, MonadHold t m, MonadFix m)
    => Dynamic t Double -> Point -> ReactiveProgram t m (Event t ())
zoomInButton hoverAlpha pos = do
    systemDraw $ uncurry translated pos <$> button <$> hoverAlpha
    (() <$) <$> ffilter (onRect 0.8 0.8 pos) <$> getPointerClick
  where
    button a =
        colored
            (RGBA 0 0 0 a)
            (translated (-0.05) (0.05) (
                thickCircle 0.1 0.22 <>
                solidRectangle 0.06 0.25 <>
                solidRectangle 0.25 0.06 <>
                rotated (-pi / 4) (translated 0.35 0 (solidRectangle 0.2 0.1))
            )) <>
        colored (RGBA 0.2 0.2 0.2 a) (rectangle 0.8 0.8) <>
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.8 0.8)

zoomOutButton
    :: (PerformEvent t m, Adjustable t m, MonadIO (Performable m),
        PostBuild t m, MonadHold t m, MonadFix m)
    => Dynamic t Double -> Point -> ReactiveProgram t m (Event t ())
zoomOutButton hoverAlpha pos = do
    systemDraw $ uncurry translated pos <$> button <$> hoverAlpha
    (() <$) <$> ffilter (onRect 0.8 0.8 pos) <$> getPointerClick
  where
    button a =
        colored
            (RGBA 0 0 0 a)
            (translated (-0.05) (0.05) (
                thickCircle 0.1 0.22 <>
                solidRectangle 0.25 0.06 <>
                rotated (-pi / 4) (translated 0.35 0 (solidRectangle 0.2 0.1))
            )) <>
        colored (RGBA 0.2 0.2 0.2 a) (rectangle 0.8 0.8) <>
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.8 0.8)

zoomSlider
    :: (PerformEvent t m, Adjustable t m, MonadIO (Performable m),
        PostBuild t m, MonadHold t m, MonadFix m)
    => Dynamic t Double -> Point -> Dynamic t Double -> ReactiveProgram t m (Event t Double)
zoomSlider hoverAlpha pos factor = do
    systemDraw $ uncurry translated pos <$> (slider <$> hoverAlpha <*> factor)
    click <- ffilter (onRect 0.8 3.0 pos) <$> getPointerClick
    release <- ffilter not <$> updated <$> isPointerDown
    dragging <- holdDyn False $ mergeWith (&&) [True <$ click, False <$ release]
    pointer <- getPointerPosition
    return $ zoomFromPoint <$> mergeWith const [gateDyn dragging (updated pointer), click]
  where
    zoomFromPoint (_x, y) = zoomIncrement ** (scaleRange (-1.4, 1.4) (-10, 10) (y - snd pos))
    yFromZoom z = scaleRange (-10, 10) (-1.4, 1.4) (logBase zoomIncrement z)
    slider a z = let yoff = yFromZoom z in
        colored
            (RGBA 0 0 0 a)
            (translated (-1.1) yoff $ scaled 0.5 0.5 $
                 lettering (T.pack (show (round (z * 100) :: Int) ++ "%"))) <>
        colored (RGBA 0 0 0 a) (translated 0 yoff (solidRectangle 0.8 0.2)) <>
        colored (RGBA 0.2 0.2 0.2 a) (rectangle 0.25 2.8) <>
        colored (RGBA 0.8 0.8 0.8 a) (solidRectangle 0.25 2.8)

zoomIncrement :: Double
zoomIncrement = 8 ** (1/10)

onRect :: Double -> Double -> Point -> Point -> Bool
onRect w h (x1, y1) (x2, y2) = abs (x1 - x2) < w / 2 && abs (y1 - y2) < h / 2

scaleRange :: (Double, Double) -> (Double, Double) -> Double -> Double
scaleRange (a1, b1) (a2, b2) x = min b2 $ max a2 $ (x - a1) / (b1 - a1) * (b2 - a2) + a2
