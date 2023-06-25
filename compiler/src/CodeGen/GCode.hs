module CodeGen.GCode 
  ( GInstr (..)
  , compileSCProg
  ) where 


import qualified Lambda.Syntax as S
import qualified Lambda.SCCompiler as SC

import Debug.Trace (trace)

data GInstr = Begin
            | End

            -- stack meta ops
            | MkAp 
            | Eval
            | Unwind
            | Return
            | Print
            | Alloc Int

            -- stack manipulation
            | PushGlobal String
            | Push Int
            | Update Int
            | Pop Int
            | Slide Int

            -- builtin funcs
            | Neg
            | Add
            | Sub
            | If
            | FatBar
            | Cons
            | Head
            | Tail

            -- pseudo-instruction
            | GlobStart String Int

            -- constants
            | PushInt Int
            | PushChar Char
            | PushBool Bool
            | PushNil
            | PushFail
            | PushError

            -- jumps
            | Jump   Int
            | JFalse Int
            | Label  Int

instance Show GInstr where 
  show Begin = "Begin"
  show End = "End"
  show MkAp = "MkAp"
  show Eval = "Eval"
  show Unwind = "Unwind"
  show Return = "Return"
  show Print = "Print"
  show (Alloc n) = "Alloc" ++ show n
  show (PushGlobal s) = "PushGlobal " ++ s
  show (Push n) = "Push " ++ show n
  show (Update n) = "Update " ++ show n
  show (Pop n) = "Pop " ++ show n
  show (Slide n) = "Slide " ++ show n
  show Neg = "Neg"
  show Add = "Add"
  show Sub = "Sub"
  show If = "If"
  show FatBar = "FatBar"
  show Cons = "Cons"
  show Head = "Head"
  show Tail = "Tail"
  show (GlobStart s n) = unwords ["GlobStart", s, show n]
  show (PushInt n) = "PushInt " ++ show n
  show (PushChar c) = "PushChar " ++ show c
  show (PushBool b) = "PushBool " ++ show b
  show PushNil = "PushNil"
  show PushFail = "PushFail"
  show PushError = "PushError"
  show (Jump l)   = "Jump L" ++ show l
  show (JFalse l) = "JFalse L" ++ show l
  show (Label l)  = "Label L" ++ show l



compileSCProg :: SC.Prog -> [GInstr]
compileSCProg (SC.Prog scs main) = 
  let prelude = 
        [ Begin
        , PushGlobal "$Prog"
        , Eval
        , Print
        , End
        ]
      
      sc_lib = concatMap compileSC scs ++ compileSC (SC.SC "$Prog" [] main)
   in prelude ++ sc_lib ++ concat builtins


-- | F compilation scheme
compileSC :: SC.SC -> [GInstr]
compileSC sc = 
  let globstart = GlobStart (SC.scName sc) (SC.scArity sc)
      
      -- R compilation scheme (resolve context)
      sc_params = SC.scParams sc
      sc_depth = length sc_params -- initial depth happens to equal to the number of args on the stack
      sc_offsets = zip sc_params (enumDescending sc_depth)
        
      -- R compilation scheme (compile)
      body_code = trace ("Compiling SC: " ++ show sc) 
        $ compileExpr sc_offsets sc_depth (SC.scBody sc) ++ [Update (sc_depth + 1), Pop sc_depth, Unwind]
   in globstart : body_code
  where 
    enumDescending :: Enum a => a -> [a]
    enumDescending start = enumFromThen start (pred start)


--------------------------------------------------------------------------------
-- Expression Compilation


-- Offsets Type

type Offsets = [(String, Int)]

pushOffsets :: [(String, Int)] -> Offsets -> Offsets
pushOffsets = (++)

pushOffset :: String -> Int -> Offsets -> Offsets
pushOffset name offset = ((name, offset) :)

lookupOffset :: String -> Offsets -> Int
lookupOffset name offsets = 
  case lookup name offsets of 
    Nothing -> error $ "No identifier: " ++ name
    Just o -> o


-- | C Compilation scheme
compileExpr :: Offsets -> Int -> S.Exp -> [GInstr]

compileExpr _ _ (S.Term (S.Constant c)) = [compileConstant c]
compileExpr _ _ (S.Term (S.Function f)) = [PushGlobal ('$' : show f)]
compileExpr _ _ (S.Term (S.Variable sc@('$' : _))) = [PushGlobal sc]
compileExpr offsets depth (S.Term (S.Variable v)) = [Push (depth - lookupOffset v offsets)]

compileExpr offsets depth (S.Apply exp1 exp2) = 
  let exp2_code = compileExpr offsets depth exp2
      exp1_code = compileExpr offsets (depth + 1) exp1
   in exp2_code ++ exp1_code ++ [MkAp]

compileExpr offsets depth (S.Let (var, val) body) = 
  let val_code = compileExpr offsets depth val 

      body_offsets = pushOffset var (depth + 1) offsets
      body_code = compileExpr body_offsets (depth + 1) body

   in val_code ++ body_code ++ [Slide 1]

compileExpr offsets depth (S.Letrec binds body) = 
  let (offsets', depth') = lrBindsContext offsets depth binds

      binds_code = compileLRBinds offsets' depth' binds
      body_code = compileExpr offsets' depth' body

   in binds_code ++ body_code ++ [Slide (depth' - depth)]

compileExpr _ _ l@(S.Lambda _ _) = error $ "Lambda in supercombinator: " ++ show l

compileConstant :: S.Constant -> GInstr
compileConstant (S.CNat n) = PushInt n
compileConstant (S.CChar c) = PushChar c
compileConstant (S.CBool b) = PushBool b
compileConstant S.CNil = PushNil
compileConstant S.CFail = PushFail
compileConstant S.CError = PushError


compileLRBinds :: Offsets -> Int -> [(String, S.Exp)] -> [GInstr]
compileLRBinds offsets depth binds =
  let n = length binds
      binds_code = concat $ zipWith compileEnumBind [n..1] (map snd binds)

   in Alloc n : binds_code
  where 
    compileEnumBind b_n b_val = 
      compileExpr offsets depth b_val ++ [Update b_n]

lrBindsContext :: Offsets -> Int -> [(String, S.Exp)] -> (Offsets, Int)
lrBindsContext offsets depth binds = 
  let bind_offsets = zipWith (\bind_n (bind_v, _) -> (bind_v, bind_n + depth)) 
                             [1..]
                             binds

      offsets' = pushOffsets bind_offsets offsets
      depth'   = depth + length binds
   in (offsets', depth')


--------------------------------------------------------------------------------
-- Builtins

builtins :: [[GInstr]]
builtins = 
  [ builtinNeg
  , builtinPlus

  , builtinCons
  , builtinHead
  , builtinTail

  , builtinIf
  ]

builtinNeg :: [GInstr]
builtinNeg = 
  [ GlobStart "$NEG" 1 
  , Eval 
  , Neg
  , Update 1
  , Return
  ]

builtinPlus :: [GInstr]
builtinPlus = 
  [ GlobStart "$+" 2
  , Push 1
  , Eval
  , Add
  , Update 3
  , Pop 2
  , Return
  ]

builtinCons :: [GInstr]
builtinCons = 
  [ GlobStart "$CONS" 2
  , Cons 
  , Update 1 
  , Return
  ]

builtinHead :: [GInstr]
builtinHead =
  [ GlobStart "$HEAD" 1
  , Eval
  , Head
  , Eval
  , Update 1
  , Unwind
  ]

builtinTail :: [GInstr]
builtinTail =
  [ GlobStart "$TAIL" 1
  , Eval
  , Tail
  , Eval
  , Update 1
  , Unwind
  ]

builtinIf :: [GInstr]
builtinIf = 
  [ GlobStart "$IF" 3
  , Eval

  , JFalse 1
  , Push 1
  , Jump 2

  , Label 1
  , Push 2

  , Label 2
  , Eval
  , Update 4
  , Pop 3
  , Unwind
  ]