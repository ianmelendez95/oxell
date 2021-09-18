{-# LANGUAGE TupleSections #-}

module Lambda.SCCompiler
  ( Prog (..)
  , SC (..)
  , compileExpr
  , compileSCs) where

import Data.List (foldl1', (\\), intersect)
import Data.Bifunctor (second)
import qualified Control.Monad.State.Lazy as ST
import qualified Lambda.Syntax as S

import Debug.Trace (trace, traceShowId)


data Prog = Prog [SC] S.Exp

-- traverseProgs :: [Prog] -> ([SC], [S.Exp])
-- traverseProgs = mconcat . map (\(Prog scs expr) -> (scs, [expr]))

appendProgs :: (S.Exp -> S.Exp -> S.Exp) -> Prog -> Prog -> Prog
appendProgs ef (Prog scs1 e1) (Prog scs2 e2) = Prog (scs1 ++ scs2) (ef e1 e2)

-- mapProg :: (S.Exp -> S.Exp) -> Prog -> Prog
-- mapProg f (Prog scs e) = Prog scs (f e)


data SuperComb = Let (String, SuperComb) SuperComb
               | Letrec [(String, SuperComb)] SuperComb
               | Term S.Term
               | App SuperComb SuperComb

               -- 'n'ary combinator, one that takes arguments
               -- NComb name params free_vars bound_vars body
               -- where 'bound' here means bound by the outer context, not the combinator
               | NComb [String] SuperComb
               deriving Show

data SC = SC {
  scName :: String,
  scParams :: [String],
  scBody :: S.Exp
}

instance Show Prog where
  show (Prog scs expr) = unlines (map show scs ++ [replicate 80 '-', show expr])

instance Show SC where
  show (SC name args expr) = unwords (name : args) ++ " = " ++ show expr

type SCS = ST.State SCEnv

data SCEnv = SCEnv {
  scenvSCCount :: Integer,
  scenvCombs :: [SC]
}


mkApp :: [SuperComb] -> SuperComb
mkApp = foldl1' App

emptySCEnv :: SCEnv
emptySCEnv = SCEnv { scenvSCCount = 0, scenvCombs = [] }

newSCName :: SCS String
newSCName =
  do ST.modify (\scenv@SCEnv{ scenvSCCount = c } -> scenv{ scenvSCCount = c+1 })
     cur_count <- ST.gets scenvSCCount
     pure $ '$' : show cur_count


--------------------------------------------------------------------------------
-- Interface


compileExpr :: S.Exp -> Prog
compileExpr expr = 
  liftSuperCombs . traceShowId . joinSuperCombs . traceShowId . exprToSuperComb $ expr
     
{-# DEPRECATED compileSCs "Use compileExpr" #-}
compileSCs :: S.Exp -> Prog
compileSCs = compileExpr


--------------------------------------------------------------------------------
-- Lambda -> SuperComb


-- exprToSuperComb :: S.Exp -> SCS SuperComb

-- exprToSuperComb (S.Let bind body) = 
--   Let <$> compileBinding bind <*> exprToSuperComb body

-- exprToSuperComb (S.Letrec binds body) = 
--   do let bindVars' = bindVars (map fst binds)

--      binds' <- mapM ((fmap . fmap) bindVars' . compileBinding) binds
--      body'  <- bindVars' <$> exprToSuperComb body
--      pure $ Letrec binds' body'

-- exprToSuperComb (S.Term t) = pure $ Term t

-- exprToSuperComb (S.Apply e1 e2) = 
--   App <$> exprToSuperComb e1 <*> exprToSuperComb e2

-- exprToSuperComb (S.Lambda var body) =
--   do sc_name <- newSCName
--      body_sc <- exprToSuperComb body
--      pure $ NComb sc_name [var] (bindVar var body_sc)


exprToSuperComb :: S.Exp -> SuperComb

exprToSuperComb (S.Let bind body) = 
  Let (compileBinding bind) (exprToSuperComb body)

exprToSuperComb (S.Letrec binds body) = 
  let binds' = map (fmap exprToSuperComb) binds
      body'  = exprToSuperComb body
   in Letrec binds' body'

exprToSuperComb (S.Term t) = Term t

exprToSuperComb (S.Apply e1 e2) = 
  App (exprToSuperComb e1) (exprToSuperComb e2)

exprToSuperComb (S.Lambda var body) = NComb [var] (exprToSuperComb body)


-- compiles the value as normal, but also 
-- when value is an nary combinator, 
-- appends the binding name to the combinator name 
-- for debugging purposes
compileBinding :: (String, S.Exp) -> (String, SuperComb)
compileBinding (bvar, bvalue) = 
  do let sc_bvalue = exprToSuperComb bvalue
         sc_bvalue' = case sc_bvalue of 
                        NComb sc_params sc_body -> 
                          NComb sc_params sc_body
                        _ -> sc_bvalue
      in (bvar, sc_bvalue')

-- Establishes a new bound variable in the supercombinator
-- context.
-- As a consequence, all contained supercombinators have the new 
-- bound variable as a parameter (if variable is free within the combinator),
-- and the combinator is replaced with an application of said combinator to 
-- the bound variable
bindVar :: String -> SuperComb -> SuperComb
bindVar var = bindVars [var]

-- see: bindVar
bindVars :: [String] -> SuperComb -> SuperComb
bindVars vars l@(Let (bvar, bval) body) = 
  let non_bvar_vars = filter (bvar ==) vars
      bindVars' = bindVars non_bvar_vars
   in if null non_bvar_vars
        then l
        else Let (bvar, bindVars' bval) (bindVars' body)
bindVars vars l@(Letrec binds body) = 
  let non_bvar_vars = vars \\ map fst binds
   in if null non_bvar_vars
        then l
        else let bindVars' = bindVars non_bvar_vars
              in Letrec (map (second bindVars') binds) (bindVars' body)
bindVars _ t@(Term _) = t
bindVars vars (App e1 e2) = App (bindVars vars e1) (bindVars vars e2)
bindVars vars c@(NComb c_params c_body) = 
  -- free_sc_vars = vars (to be bound) that are free in combinator
  let free_sc_vars = vars `intersect` collectFreeVars c_params c_body
   in if null free_sc_vars
        then c
        else let sc = NComb (free_sc_vars ++ c_params) c_body 
                 sc_args = map (Term . S.Variable) free_sc_vars
              in mkApp (sc : sc_args)


collectFreeVars :: [String] -> SuperComb -> [String]
collectFreeVars bound_vars (Let (bvar, bvalue) body) =
  let bound_vars' = bvar : bound_vars
   in collectFreeVars bound_vars' bvalue ++ collectFreeVars bound_vars' body
collectFreeVars bound_vars (Letrec binds body) =
  let bound_vars' = map fst binds ++ bound_vars
   in concatMap (collectFreeVars bound_vars' . snd) binds ++ collectFreeVars bound_vars' body
collectFreeVars bound_vars (Term (S.Variable v)) = [v | v `notElem` bound_vars]
collectFreeVars _ (Term _) = []
collectFreeVars bound_vars (App e1 e2) = collectFreeVars bound_vars e1 ++ collectFreeVars bound_vars e2
collectFreeVars bound_vars (NComb params body) = collectFreeVars (params ++ bound_vars) body


--------------------------------------------------------------------------------
-- SuperComb -> Lambda


liftSuperCombs :: SuperComb -> Prog
liftSuperCombs (Let (bvar, bval) body) = 
  appendProgs (\bval' body' -> S.Let (bvar, bval') body') 
              (liftSuperCombs bval) 
              (liftSuperCombs body)
liftSuperCombs (Letrec binds body) = 
  let (binds_scs, binds') = liftBindings binds
      (Prog body_scs body') = liftSuperCombs body
   in Prog (binds_scs ++ body_scs) (S.Letrec binds' body')
  
-- TODO: consider renaming free vars that match named supercombs
liftSuperCombs (Term t) = Prog [] (S.Term t)
liftSuperCombs (App sc1 sc2) = 
  appendProgs S.Apply (liftSuperCombs sc1) (liftSuperCombs sc2)
liftSuperCombs (NComb params body) = 
  let (Prog b_scs body') = liftSuperCombs body
      new_sc = SC {
        scName = "TODO GEN NAME",
        scParams = params,
        scBody = body'
      }
   in Prog (new_sc : b_scs) (S.mkApply . map S.mkVariable $ "TODO GEN NAME" : params)


liftBindings :: [(String, SuperComb)] -> ([SC], [(String, S.Exp)])
liftBindings = mconcat . map liftBinding
  where
    -- 'lift' the binding, retrieving the supercombinators
    -- and the new binding
    --
    -- returns the binding as a singleton list so it can be 
    -- simply concatenated
    liftBinding :: (String, SuperComb) -> ([SC], [(String, S.Exp)])
    liftBinding (var, val) = 
      let (Prog scs val') = liftSuperCombs val
        in (scs, [(var, val')])


-- | Identifies directly nested supercombinators,
-- | and attempts to join them
-- |
-- | e.g.
-- |   ($ y = ($ x = y))
-- |   => ($ y x = y)
-- | 
-- | This has the consequence of addressing eventual full
-- | eta reductions as described in 
-- | section 13.3.1 "Eliminating Redundant Parameters"
joinSuperCombs :: SuperComb -> SuperComb
joinSuperCombs (Let (var, val) body) = Let (var, joinSuperCombs val) body
joinSuperCombs (Letrec binds body) = Letrec (map (joinSuperCombs <$>) binds) body
joinSuperCombs t@(Term _) = t
joinSuperCombs (App sc1 sc2) = App (joinSuperCombs sc1) (joinSuperCombs sc2)
joinSuperCombs (NComb out_params in_sc) = 
  case joinSuperCombs in_sc of 
    in_sc'@(NComb in_params in_body) -> 
      if null (out_params `intersect` in_params) -- don't have shared parameters
        then trace "DID" NComb (out_params ++ in_params) in_body
        else trace "DID NOT" NComb out_params in_sc'
    in_sc' -> NComb out_params in_sc'
   


