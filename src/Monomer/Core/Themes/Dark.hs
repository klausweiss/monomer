{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Monomer.Core.Themes.Dark (
  darkTheme
) where

import Control.Lens ((&), (^.), (.~), (?~), non)
import Data.Default

import Monomer.Core.Combinators
import Monomer.Core.Style
import Monomer.Graphics.Color
import Monomer.Graphics.Types

import qualified Monomer.Lens as L

darkTheme :: Theme
darkTheme = Theme {
  _themeBasic = darkBasic,
  _themeHover = darkHover,
  _themeFocus = darkFocus,
  _themeDisabled = darkDisabled
}

textPadding :: Padding
textPadding = padding 3 <> paddingB 2

normalFont :: TextStyle
normalFont = def
  & L.font ?~ Font "Regular"
  & L.fontSize ?~ FontSize 16
  & L.fontColor ?~ white

titleFont :: TextStyle
titleFont = def
  & L.font ?~ Font "Bold"
  & L.fontSize ?~ FontSize 20
  & L.fontColor ?~ white

inputStyle :: StyleState
inputStyle = def
  & L.text ?~ normalFont
  & L.bgColor ?~ darkGray
  & L.border ?~ border 1 gray
  & L.padding ?~ textPadding

numericInputStyle :: StyleState
numericInputStyle = inputStyle
  & L.text . non def . L.alignH ?~ ARight

listViewItemStyle :: StyleState
listViewItemStyle = def
  & L.text ?~ normalFont
  & L.text . non def . L.alignH ?~ ALeft
  & L.padding ?~ paddingH 10

listViewItemSelectedStyle :: StyleState
listViewItemSelectedStyle = listViewItemStyle
  & L.bgColor ?~ darkGray

darkBasic :: ThemeState
darkBasic = def
  & L.fgColor .~ blue
  & L.hlColor .~ white
  & L.text .~ normalFont
  & L.emptyOverlayColor .~ (darkGray & L.a .~ 0.8)
  & L.btnStyle . L.bgColor ?~ darkGray
  & L.btnStyle . L.text ?~ normalFont
  & L.btnStyle . L.padding ?~ (paddingV 3 <> paddingH 5)
  & L.btnMainStyle . L.bgColor ?~ blue
  & L.btnMainStyle . L.text ?~ normalFont
  & L.btnMainStyle . L.padding ?~ (paddingV 3 <> paddingH 5)
  & L.checkboxWidth .~ 25
  & L.checkboxStyle . L.fgColor ?~ gray
  & L.dialogFrameStyle . L.bgColor ?~ gray
  & L.dialogFrameStyle . L.border ?~ border 1 darkGray
  & L.dialogTitleStyle . L.text ?~ titleFont <> textLeft
  & L.dialogTitleStyle . L.padding ?~ padding 5
  & L.dialogBodyStyle . L.text ?~ normalFont
  & L.dialogBodyStyle . L.padding ?~ padding 5
  & L.dialogBodyStyle . L.sizeReqW ?~ minWidth 200
  & L.dialogBodyStyle . L.sizeReqH ?~ minHeight 100
  & L.dialogButtonsStyle . L.padding ?~ padding 5
  & L.dropdownMaxHeight .~ 200
  & L.dropdownListStyle . L.bgColor ?~ black
  & L.dropdownItemStyle .~ listViewItemStyle
  & L.dropdownItemSelectedStyle .~ listViewItemSelectedStyle
  & L.inputFloatingStyle .~ numericInputStyle
  & L.inputIntegralStyle .~ numericInputStyle
  & L.inputTextStyle .~ inputStyle
  & L.labelStyle . L.text ?~ normalFont
  & L.labelStyle . L.padding ?~ textPadding
  & L.listViewItemStyle .~ listViewItemStyle
  & L.listViewItemSelectedStyle .~ listViewItemSelectedStyle
  & L.radioWidth .~ 25
  & L.radioStyle . L.fgColor ?~ gray
  & L.scrollBarColor .~ (gray & L.a .~ 0.2)
  & L.scrollThumbColor .~ (darkGray & L.a .~ 0.6)
  & L.scrollWidth .~ 10

darkHover :: ThemeState
darkHover = darkBasic
  & L.scrollBarColor .~ (gray & L.a .~ 0.4)
  & L.scrollThumbColor .~ (darkGray & L.a .~ 0.8)
  & L.btnStyle . L.bgColor ?~ lightGray
  & L.btnStyle . L.cursorIcon ?~ CursorHand
  & L.btnMainStyle . L.bgColor ?~ lightBlue
  & L.btnMainStyle . L.cursorIcon ?~ CursorHand
  & L.checkboxStyle . L.fgColor ?~ white
  & L.checkboxStyle . L.cursorIcon ?~ CursorHand
  & L.dropdownItemStyle . L.bgColor ?~ gray
  & L.listViewItemStyle . L.bgColor ?~ gray
  & L.radioStyle . L.fgColor ?~ white
  & L.radioStyle . L.cursorIcon ?~ CursorHand

darkFocus :: ThemeState
darkFocus = darkBasic
  & L.checkboxStyle . L.fgColor ?~ white
  & L.dropdownItemStyle . L.bgColor ?~ lightGray
  & L.dropdownItemSelectedStyle . L.bgColor ?~ gray
  & L.inputFloatingStyle . L.border ?~ border 1 lightSkyBlue
  & L.inputIntegralStyle . L.border ?~ border 1 lightSkyBlue
  & L.inputTextStyle . L.border ?~ border 1 lightSkyBlue
  & L.listViewItemStyle . L.bgColor ?~ lightGray
  & L.listViewItemSelectedStyle . L.bgColor ?~ gray
  & L.radioStyle . L.fgColor ?~ white

darkDisabled :: ThemeState
darkDisabled = darkBasic
