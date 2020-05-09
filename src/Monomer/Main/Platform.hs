{-# LANGUAGE BangPatterns #-}

module Monomer.Main.Platform where

import Control.Monad.IO.Class
--import NanoVG (Context(..), createGL3, CreateFlags(..), createFont, FileName(..), beginFrame, endFrame)
import NanoVG (Context(..), beginFrame, endFrame)

import qualified Graphics.Rendering.OpenGL as GL
import qualified SDL
import qualified SDL.Input.Mouse as Mouse

import Monomer.Common.Types

getCurrentMousePos :: (MonadIO m) => m Point
getCurrentMousePos = do
  SDL.P (SDL.V2 x y) <- Mouse.getAbsoluteMouseLocation
  return $ Point (fromIntegral x) (fromIntegral y)

getWindowSize :: (MonadIO m) => SDL.Window -> m Rect
getWindowSize window = do
  SDL.V2 fbWidth fbHeight <- SDL.glGetDrawableSize window
  return (Rect 0 0 (fromIntegral fbWidth) (fromIntegral fbHeight))

doInDrawingContext :: (MonadIO m) => SDL.Window -> Context -> m s -> m s
doInDrawingContext window c action = do
  SDL.V2 fbWidth fbHeight <- SDL.glGetDrawableSize window
  let !pxRatio = fromIntegral fbWidth / fromIntegral fbHeight

  liftIO $ GL.clear [GL.ColorBuffer]
  liftIO $ beginFrame c fbWidth fbHeight pxRatio

  ret <- action

  liftIO $ endFrame c
  SDL.glSwapWindow window
  return ret
