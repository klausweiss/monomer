{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{- HLINT ignore "Use foldr" -}

module Monomer.Widget.Widgets.TextField (
  textField,
  textField_
) where

import Control.Applicative ((<|>))
import Control.Lens (ALens')
import Data.Default
import Data.Maybe
import Data.Text (Text)

import qualified Data.Text as T

import Monomer.Widget.Types
import Monomer.Widget.Widgets.InputField
import Monomer.Widget.Widgets.WidgetCombinators

data TextFieldCfg s e = TextFieldCfg {
  _tfcValid :: Maybe (WidgetValue s Bool),
  _tfcMaxLength :: Maybe Int,
  _tfcSelectOnFocus :: Maybe Bool,
  _tfcOnChange :: [Text -> e],
  _tfcOnChangeReq :: [WidgetRequest s]
}

instance Default (TextFieldCfg s e) where
  def = TextFieldCfg {
    _tfcValid = Nothing,
    _tfcMaxLength = Nothing,
    _tfcSelectOnFocus = Nothing,
    _tfcOnChange = [],
    _tfcOnChangeReq = []
  }

instance Semigroup (TextFieldCfg s e) where
  (<>) t1 t2 = TextFieldCfg {
    _tfcValid = _tfcValid t2 <|> _tfcValid t1,
    _tfcMaxLength = _tfcMaxLength t2 <|> _tfcMaxLength t1,
    _tfcSelectOnFocus = _tfcSelectOnFocus t2 <|> _tfcSelectOnFocus t1,
    _tfcOnChange = _tfcOnChange t1 <> _tfcOnChange t2,
    _tfcOnChangeReq = _tfcOnChangeReq t1 <> _tfcOnChangeReq t2
  }

instance Monoid (TextFieldCfg s e) where
  mempty = def

instance ValidInput (TextFieldCfg s e) s where
  validInput field = def {
    _tfcValid = Just (WidgetLens field)
  }

instance SelectOnFocus (TextFieldCfg s e) where
  selectOnFocus sel = def {
    _tfcSelectOnFocus = Just sel
  }

instance MaxLength (TextFieldCfg s e) where
  maxLength len = def {
    _tfcMaxLength = Just len
  }

instance OnChange (TextFieldCfg s e) Text e where
  onChange fn = def {
    _tfcOnChange = [fn]
  }

instance OnChangeReq (TextFieldCfg s e) s where
  onChangeReq req = def {
    _tfcOnChangeReq = [req]
  }

instance Default Text where
  def = T.empty

textField :: ALens' s Text -> WidgetInstance s e
textField field = textField_ field def

textField_ :: ALens' s Text -> TextFieldCfg s e -> WidgetInstance s e
textField_ field config = inputField where
  inputConfig = inputFieldCfg (WidgetLens field) fromText id
  fromText = textToText (_tfcMaxLength config)
  inputField = inputField_ "textField" inputConfig {
    _ifcValid = _tfcValid config,
    _ifcAcceptInput = acceptInput (_tfcMaxLength config),
    _ifcSelectOnFocus = fromMaybe False (_tfcSelectOnFocus config),
    _ifcOnChange = _tfcOnChange config,
    _ifcOnChangeReq = _tfcOnChangeReq config
  }

textToText :: Maybe Int -> Text -> Maybe Text
textToText Nothing text = Just text
textToText (Just len) text
  | T.length text <= len = Just text
  | otherwise = Nothing

acceptInput :: Maybe Int -> Text -> Bool
acceptInput Nothing _ = True
acceptInput (Just len) text = T.length text <= len
