module Lambda.Syntax 
  ( Exp (..)
  , Variable (..)
  , Function (..)
  , Constant (..)
  , ToLambda (..)
  , ToConstant (..)
  , showMarked
  , varName
  , mapVarName
  , fromConstantToken
  , fromFunctionToken
  ) where 

import Prettyprinter ( (<+>), backslash, dot )
import Prettyprinter.Render.Util.SimpleDocTree (treeForm, renderSimplyDecorated)
import Data.Text (Text, unpack, pack)

import qualified Lambda.Token as T
import Lambda.Pretty

data Exp = Constant Constant 
         | Function Function
         | Variable Variable 
         | Apply Exp Exp 
         | Lambda String Exp

data Function = FPlus
              | FMinus 
              | FMult
              | FDiv
              | FAnd
              | FOr 
              | FNot
              | FIf
              | FCons 
              | FHead 
              | FTail
              | FY   -- The Glorious Y Combinator
              | FEq

data Constant = CNat Int
              | CChar Char
              | CBool Bool 
              | CNil

data Variable = RawVar String 
              | FreeVar String 
              | BoundVar String
              -- deriving Show

--------------
-- ToLambda --
--------------

class ToLambda a where 
  toLambda :: a -> Exp

----------------
-- ToConstant --
----------------

class ToConstant a where 
  toConstant :: a -> Constant

instance ToConstant Int where 
  toConstant = CNat
instance ToConstant Char where
  toConstant = CChar
instance ToConstant Bool where
  toConstant = CBool

----------------------
-- Token Conversion --
----------------------

fromConstantToken :: T.Constant -> Exp 
fromConstantToken (T.CNat n)   = Constant (CNat n) 
fromConstantToken (T.CChar n)  = Constant (CChar n) 
fromConstantToken (T.CBool b)  = Constant (CBool b) 

fromFunctionToken :: T.Function -> Exp
fromFunctionToken T.FPlus  = Function FPlus
fromFunctionToken T.FMinus = Function FMinus 
fromFunctionToken T.FMult  = Function FMult
fromFunctionToken T.FDiv   = Function FDiv
fromFunctionToken T.FAnd   = Function FAnd
fromFunctionToken T.FOr    = Function FOr 
fromFunctionToken T.FNot   = Function FNot
fromFunctionToken T.FIf    = Function FIf
fromFunctionToken T.FCons  = Function FCons
fromFunctionToken T.FHead  = Function FHead
fromFunctionToken T.FTail  = Function FTail
fromFunctionToken T.FY     = Function FY

---------
-- Ops --
---------

varName :: Variable -> String 
varName (RawVar n) = n
varName (FreeVar n) = n
varName (BoundVar n) = n

mapVarName :: (String -> String) -> Variable -> Variable 
mapVarName f (RawVar n) = RawVar (f n)
mapVarName f (FreeVar n) = FreeVar (f n)
mapVarName f (BoundVar n) = BoundVar (f n)

--------------
-- Showing --
--------------

-- renderSimplyDecorated
--    :: Monoid out
--    => (Text -> out)       -- ^ Render plain 'Text'
--    -> (ann -> out -> out) -- ^ How to modify an element with an annotation
--    -> SimpleDocTree ann
--    -> out
showMarked :: Exp -> String 
showMarked expr = unpack $ renderSimplyDecorated id renderMarked (treeForm $ prettyStream expr)
  where 
    renderMarked :: LambdaAnn -> Text -> Text 
    renderMarked ABoundVar var = var <> pack ":b"
    renderMarked AFreeVar var = var <> pack ":f"
    renderMarked ARawVar var = var <> pack ":r"
    renderMarked _ var = var

instance Show Exp where 
  show = pShow

instance Show Function where
  show FPlus  = "+"
  show FMinus = "-"
  show FMult  = "*"
  show FDiv   = "/"
  show FAnd   = "AND"
  show FOr    = "OR"
  show FNot   = "NOT"
  show FIf    = "IF"
  show FCons  = "CONS"
  show FHead  = "HEAD"
  show FTail  = "TAIL"
  show FEq    = "="
  show FY     = "Y"

instance Show Constant where 
  show (CNat n)      = show n
  show (CChar c)     = "\'" ++ [c] ++ "\'"
  show (CBool True)  = "TRUE"
  show (CBool False) = "FALSE"
  show CNil          = "NIL"

instance Show Variable where 
  show (RawVar var) = var
  show (FreeVar var) = var
  show (BoundVar var) = var

------------------
-- Pretty Print --
------------------

instance PrettyLambda Exp where 
  prettyDoc = mkPrettyDocFromParenS sPretty

sPretty :: Exp -> PrettyParenS LambdaDoc
sPretty (Constant c) = pure $ annStr AConstant (show c)
sPretty (Function f) = pure $ annStr AFunction (show f)
sPretty (Variable var) = pure $ prettyVar var
sPretty (Lambda var e) = do wrapper <- getParenWrapper 5 
                            ePretty <- tempState (setPrec 0) (sPretty e)
                            pure $ wrapper $ backslash
                                           <> annStr ABoundVar var 
                                           <> dot 
                                           <+> ePretty
sPretty (Apply e e') = do wrapper <- getParenWrapper 10
                          ePretty <- tempState (setPrec 6) (sPretty e)
                          ePretty' <- tempState (setPrec 11) (sPretty e')
                          pure $ wrapper $ ePretty <+> ePretty'

prettyVar :: Variable -> Doc LambdaAnn
prettyVar (FreeVar name)  = annStr AFreeVar name
prettyVar (BoundVar name) = annStr ABoundVar name
prettyVar (RawVar name)   = annStr ARawVar name
