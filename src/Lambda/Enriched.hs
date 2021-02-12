module Lambda.Enriched where 

import Prettyprinter
import Control.Monad.State.Lazy

import Lambda.Pretty
import Lambda.Syntax (ToLambda (..))
import qualified Lambda.Syntax as S

data Exp = Let String Exp Exp
         | Pure S.Exp
         | Apply Exp Exp 
         | Lambda String Exp

--------------
-- ToLambda --
--------------

instance ToLambda Exp where
  toLambda (Let var val body) = S.Apply (S.Lambda var (toLambda body)) (toLambda val)
  toLambda (Apply e1 e2) = S.Apply (toLambda e1) (toLambda e2)
  toLambda (Lambda var body) = S.Lambda var (toLambda body)
  toLambda (Pure expr) = expr

----------------------
-- Enriched -> Pure --
----------------------

enrichedToLambda :: Exp -> S.Exp 
enrichedToLambda = toLambda

instance Show Exp where 
  show = pShow

------------------
-- Pretty Print --
------------------

data ParenState = ParenState {
    parenPrec :: Int,
    parenStyle :: AParen
  }

type LambdaDoc = Doc LambdaAnn
type PrettyExp = State ParenState
type ParenWrapper = (LambdaDoc -> LambdaDoc)

instance PrettyLambda Exp where 
  prettyDoc = prettyExpDoc

initParenState :: ParenState
initParenState = ParenState 0 AParenMagenta

prettyExpDoc :: Exp -> Doc LambdaAnn
prettyExpDoc expr = evalState (sPretty expr) initParenState 

sPretty :: Exp -> PrettyExp LambdaDoc
sPretty (Pure expr) = pure $ prettyDoc expr
sPretty (Let var val body) = pure $ pretty "let" <+> pretty var 
                                                 <+> pretty "=" 
                                                 <+> prettyDoc val 
                                                 <+> pretty "in"
                                                 <+> prettyDoc body
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

tempState :: PrettyExp () -> PrettyExp a -> PrettyExp a
tempState change pe = do s <- get 
                         change
                         res <- pe
                         put s
                         return res

setPrec :: Int -> PrettyExp ()
setPrec prec = modify (\ps -> ps { parenPrec = prec })

-- | main reason for using state, so we can get the paren wrapper and update the paren state
-- | in one swoop (still probably too obfuscated to be worth it)
getParenWrapper :: Int -> PrettyExp ParenWrapper
getParenWrapper prec = do pPrec <- gets parenPrec
                          if pPrec <= prec
                            then pure id 
                            else getWrapper
  where 
    getWrapper :: PrettyExp ParenWrapper
    getWrapper = annParens . AParen <$> (gets parenStyle <* modify updateParenStyle)

updateParenStyle :: ParenState -> ParenState
updateParenStyle pState@ParenState { parenStyle = style } 
  = pState { parenStyle = nextParenAnn style }