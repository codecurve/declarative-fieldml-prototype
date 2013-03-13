{
{-# LANGUAGE OverloadedStrings #-}
module Data.FieldML.Parser (parseFieldML) where
import Data.FieldML.LexicalAnalyser
import Data.FieldML.Level1Structure
import Control.Monad
import Data.Maybe
import Data.List
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
}
%monad { Alex }
%lexer { alexWithContinuation } { TokEOF _ }
%tokentype { Token }
%token Append { TokAppend $$ }
       As { TokAs $$ }
       Case { TokCase $$ }
       Class { TokClass $$ }
       Clone { TokClone $$ }
       Colon { TokColon $$ }
       Connect { TokConnect $$ }
       Dimensionless { TokDimensionless $$ }
       Domain { TokDomain $$ }
       Ensemble { TokEnsemble $$ }
       From { TokFrom $$ }
       HeadSep { TokHeadSep $$ }
       Hiding { TokHiding $$ }
       Import { TokImport $$ }
       Instance { TokInstance $$ }
       Let { TokLet $$ }
       Lookup { TokLookup $$ }
       My { TokMy $$ }
       Namespace { TokNamespace $$ }
       Newbase { TokNewbase $$ }
       PathSep { TokPathSep $$ }
       RightArrow { TokRightArrow $$ }
       Subset { TokSubset $$ }
       Unit { TokUnit $$ }
       Using { TokUsing $$ }
       Where { TokWhere $$ }
       CloseBracket { TokCloseBracket $$ }
       CloseCurlyBracket { TokCloseCurlyBracket $$ }
       CloseProductBracket { TokCloseProductBracket $$ }
       CloseSqBracket { TokCloseSqBracket $$ }
       Comma { TokComma $$ }
       Equal { TokEqual $$ }
       Of { TokOf $$ }
       OpenBracket { TokOpenBracket $$ }
       OpenCurlyBracket { TokOpenCurlyBracket $$ }
       OpenProductBracket { TokOpenProductBracket $$ }
       OpenSqBracket { TokOpenSqBracket $$ }
       Pipe { TokPipe $$ }
       R { TokR $$ }
       Slash { TokSlash $$ }
       ForwardSlash { TokForwardSlash $$ }
       Tilde { TokTilde $$ }
       Int { TokInt $$ }
       NamedSymbol { TokNamedSymbol $$ }
       Real { TokReal $$ }
       ScopedSymbol { TokScopedSymbol $$ }
       SignedInt { TokSignedInt $$ }
       String { TokString $$ }
       CloseBlock { TokCloseBlock $$ }

%left lowerEmpty
%left lowerSep
%left expressionSig
%left PathSep
%left expressionCombine OpenCurlyBracket OpenProductBracket As R Slash ScopedSymbol Where Int SignedInt Append Case Lookup String
%left ForwardSlash
%left Comma Pipe
%left OpenBracket
%left preferOpenSqBracket
%left OpenSqBracket
%left kindSpec RightArrow
%left NamedSymbol expression
%right unitExpression
%right unitExprEnding
%left highestEmpty
%left highestSep

%name happyParseFieldML
%error { happyError }
%%

main : namespaceContents { $1 }

namespaceContents
  : many(namespaceStatement) { L1NamespaceContents $1 }

namespaceStatement
  : startBlock(Import) maybe(fromURL) relOrAbsPath maybe(identList) maybe(hidingList) maybe(asId) closeBlock {
      L1NSImport (twoPosToSpan $1 $7) $2 $3 $4 $5 $6
    }
  | startBlock(Namespace) identifier Where namespaceContents closeBlock {
      L1NSNamespace (twoPosToSpan $1 $5) $2 $4
    }
  | startBlock(Domain) identifier many(scopedId) Equal domainDefinition orEmptyNSContents(whereNamespaceContents) closeBlock {
      L1NSDomain (twoPosToSpan $1 $7) $2 $3 $5 $6
    }
  | startBlock(Let) expression closeBlock { L1NSAssertion (twoPosToSpan $1 $3) $2 }
  | startBlock(My) identifier maybe(domainTypeAnnotation) closeBlock { L1NSNamedValue (twoPosToSpan $1 $4) $2 $3 }
  | startBlock(Class) identifier classParameters maybe(classContents) closeBlock {
      L1NSClass (twoPosToSpan $1 $5) $2 $3 (maybe [] fst $4) (maybe [] snd $4)
    }
  | startBlock(Ensemble) OpenCurlyBracket sepBy1(identifier, Comma) CloseCurlyBracket maybe(asId) closeBlock {
      L1NSEnsemble (twoPosToSpan $1 $6) $3 $5
    }
  | startBlock(Unit) identifier Equal unitDefinition closeBlock { L1NSUnit (twoPosToSpan $1 $5) $2 $4 }
  | startBlock(Instance) relOrAbsPath OpenBracket sepBy(domainType,Comma) CloseBracket maybe(instanceContents) closeBlock {
      L1NSInstance (twoPosToSpan $1 $7) $2 $4 (maybe [] fst $6) (maybe [] snd $6)
    }

classParameters : OpenBracket sepBy(classParameter,Comma) CloseBracket { $2 }
classParameter : scopedId maybe(kindAnnotation) { ($1, fromMaybe (L1Kind []) $2) }

kindAnnotation : PathSep kindSpec { $2 }
kindSpec
  : NamedSymbol %prec kindSpec
       {% if snd $1 == "*"
            then return (L1Kind [])
            else happyError (TokNamedSymbol $1)
       }
  | OpenBracket kindSpec CloseBracket %prec kindSpec { $2 }
  | kindSpec RightArrow kindSpec %prec kindSpec { (\(L1Kind k) -> L1Kind ($1:k)) $3 }

classContents : Where classDomainFunctions classValues { ($2, $3) }
classDomainFunctions : many(classDomainFunction) { $1 }
classDomainFunction : startBlock(Domain) identifier OpenBracket sepBy1(scopedId,Comma) CloseBracket closeBlock {
   ($2, length $4)
  }
classValues : many(classValue) { $1 }
classValue : identifier domainTypeAnnotation { ($1, $2) }

instanceContents : Where many(instanceDomainFunction) many(instanceValue) { ($2, $3) }
instanceDomainFunction : startBlock(Domain) identifier OpenBracket sepBy1(domainType, Comma) CloseBracket Equal domainExpression closeBlock {
    ($2, $4, $7)
  }
instanceValue : startBlock(Let) expression closeBlock { $2 }
domainTypeAnnotation : PathSep domainType { $2 }

fromURL : From String { snd $2 }
identList :: { [L1Identifier] }
          : OpenBracket sepBy(identifier,Comma) CloseBracket { $2 }
hidingList : Hiding identList { $2 }
whereNamespaceContents : Where namespaceContents { $2 }

relOrAbsPath : Slash relPath0 { L1RelOrAbsPath (twoPosToSpan (alexPosToSrcPoint $1) (l1RelPathSS $2)) True $2 }
             | relPath { L1RelOrAbsPath (l1RelPathSS $1) False $1 }
relPath0 : {- empty -} {% do
                           (pos, _, _) <- alexGetInput                        
                           return $ L1RelPath (alexPosToSrcPoint pos) []
                       }
  | PathSep sepBy1(identifier, PathSep) %prec highestSep { L1RelPath (twoPosToSpan (alexPosToSrcPoint $1) (l1IdSS (last $2))) $2 }
relPath : sepBy1(identifier,PathSep) { L1RelPath (twoPosToSpan (l1IdSS $ head $1) (l1IdSS $ last $1)) $1 }

relOrAbsPathPossiblyIntEnd
  :: { L1RelOrAbsPathPossiblyIntEnd }
  : Slash relPath0PossiblyIntEndRev %prec lowerSep {
      case $2 of
        Left v -> L1RelOrAbsPathNoInt (if null v then alexPosToSrcPoint $1
                                                 else twoPosToSpan (alexPosToSrcPoint $1)
                                                                   (l1IdSS $ head v))
                                      True (L1RelPath (SrcSpan "-" 0 0 0 0) $ reverse v)
        Right (v, (ss, i)) ->
          L1RelOrAbsPathInt (twoPosToSpan (alexPosToSrcPoint $1)
                                          ss) True (L1RelPath (SrcSpan "-" 0 0 0 0) $ reverse v) i
     }
  | relPathPossiblyIntEndRev %prec lowerSep {
    case $1 of
      Left v -> L1RelOrAbsPathNoInt (twoPosToSpan (l1IdSS $ last v) (l1IdSS $ head v))
                                    False (L1RelPath (SrcSpan "-" 0 0 0 0) (reverse v))
      Right (v, (ss, i)) -> L1RelOrAbsPathInt (if null v then ss else twoPosToSpan (l1IdSS $ last v) ss)
                                              False (L1RelPath (SrcSpan "-" 0 0 0 0) (reverse v)) i
    }
relPath0PossiblyIntEndRev
  :: { Either [L1Identifier] ([L1Identifier], (SrcSpan, Int)) }
  : PathSep relPathPossiblyIntEndRev %prec highestSep { $2 }
  | {- empty -} %prec lowerSep { Left [] }
relPathPossiblyIntEndRev : relPathPossiblyIntEndRev PathSep identifierOrInteger %prec highestSep {%
  case ($1, $3) of
    (Right _, _) -> happyError (TokPathSep $2)
    (Left vl, Left v)  -> return $ Left (v:vl)
    (Left vl, Right i) -> return $ Right (vl, i)
                                                                                }
  | identifierOrInteger { either (Left . (:[])) (\i -> Right ([], i)) $1 }
identifierOrInteger : identifier { Left $1 }
                    | integer { Right $1 }

identifier : NamedSymbol { L1Identifier (alexPosToSrcPoint $ fst $1) (snd $1) }
scopedId : ScopedSymbol { L1ScopedID (alexPosToSrcPoint $ fst $1) (snd $1) }
asId : As identifier { $2 }

domainDefinition : Clone domainType { L1CloneDomain (alexPosToSrcPoint $1) $2 }
                 | startBlock(Subset) domainType Using expression closeBlock { L1SubsetDomain (twoPosToSpan $1 $5) $2 $4 }
                 | startBlock(Connect) domainType Using expression closeBlock { L1ConnectDomain (twoPosToSpan $1 $5) $2 $4 }
                 | domainType { L1DomainDefDomainType (l1DomainTypeSS $1) $1 }

domainType : domainHead domainExpression { L1DomainType (twoPosToSpan (fst $1) (l1DomainExpressionSS $2)) (snd $1) $2 }
domainHead
  : OpenSqBracket sepBy(domainClassRelation,Comma) CloseSqBracket HeadSep { (twoPosToSpan (alexPosToSrcPoint $1) (alexPosToSrcPoint $4), $2) }
  | {- empty -} {% do
                    (pos, _, _) <- alexGetInput
                    return (alexPosToSrcPoint pos, [])
                }
domainClassRelation : Unit unitExpression Tilde unitExpression { L1DCRUnitConstraint $2 $4 }
                    | Class relOrAbsPath OpenBracket sepBy(domainExpression,Comma) CloseBracket { L1DCRRelation $2 $4 }
                    | domainExpression Tilde domainExpression { L1DCREquality $1 $3 }

domainExpression
  :: { L1DomainExpression }
  : OpenProductBracket labelledDomains(Comma) CloseProductBracket {
      L1DomainExpressionProduct (twoPosToSpan (alexPosToSrcPoint $1) (alexPosToSrcPoint $3)) $2 
    }
  | OpenBracket domainExpression bracketDomainExpression CloseBracket {%
      $3 $2 (twoPosToSpan (alexPosToSrcPoint $1) (alexPosToSrcPoint $4))
                                                                      }
  | domainExpression RightArrow domainExpression { L1DomainExpressionFieldSignature (twoPosToSpan (l1DomainExpressionSS $1) (l1DomainExpressionSS $3))
                                                                                    $1 $3 }
  | domainExpression OpenSqBracket sepBy1(domainApplyArg,Comma) CloseSqBracket %prec OpenSqBracket {
    let ss = twoPosToSpan (l1DomainExpressionSS $1) (alexPosToSrcPoint $4) in
      foldl (\d (sv,ex) -> L1DomainExpressionApply ss d sv ex) $1 $3
    }
  | R maybeBracketedUnits {
      L1DomainExpressionReal (alexPosToSrcPoint $1) $2
    }
  | relOrAbsPathPossiblyIntEnd domainExprStartsWithPath {% $2 $1 }
  | scopedId { L1DomainVariableRef (l1ScopedIdSS $1) $1 }

domainExprStartsWithPath
  : OpenBracket sepBy1(domainExpression,Comma) CloseBracket %prec highestSep {
      \path' -> case path' of
        L1RelOrAbsPathNoInt ss ra p -> return $ L1DomainFunctionEvaluate (twoPosToSpan ss (alexPosToSrcPoint $3))
                                                                         (L1RelOrAbsPath ss ra p) $2
        L1RelOrAbsPathInt ss _ _ _ -> fail $ "Unexpected number label at " ++ show ss
    }
  | {- empty -} %prec lowerSep { \path -> return $ L1DomainReference (l1RelOrAbsPIESS path) path }

maybeBracketedUnits : bracketedUnits %prec OpenSqBracket { $1 }
                    | {- empty -} %prec preferOpenSqBracket { L1UnitExDimensionless (SrcSpan "built-in" 0 0 0 0) }
bracketedUnits : OpenSqBracket unitExpression CloseSqBracket { $2 }
domainApplyArg :: { (L1ScopedID, L1DomainExpression) }
               : scopedId Equal domainExpression { ($1, $3) }

bracketDomainExpression : {- empty -} { \ex _ -> return ex } -- Just a bracketed expression.
                        | Colon domainExpression Pipe labelledDomains(Pipe) {\shouldBeLabel ss ->
                            -- We parse the more general case and fail if it doesn't make sense...
                            let (L1LabelledDomains lTail) = $4 in
                              case shouldBeLabel of
                                (L1DomainReference _ label) -> return $
                                   L1DomainExpressionDisjointUnion ss (L1LabelledDomains ((label, $2):lTail))
                                _ -> happyError (TokColon $1)
                          }
                        | Pipe labelledDomains(Pipe) {\shouldBeLabel ss ->
                            let (L1LabelledDomains lTail) = $2 in
                              case shouldBeLabel of
                                (L1DomainReference _ label) -> return $
                                   L1DomainExpressionDisjointUnion ss (L1LabelledDomains ((label, shouldBeLabel):lTail))
                                _ -> happyError (TokPipe $1)
                                               }

labelledDomains(sep) :: { L1LabelledDomains }
                     : sepBy(labelledDomain,sep) { L1LabelledDomains $1 }
labelledDomain :: { (L1RelOrAbsPathPossiblyIntEnd, L1DomainExpression) }
               : relOrAbsPathPossiblyIntEnd Colon domainExpression { ($1, $3) }
               | relOrAbsPathPossiblyIntEnd { ($1, L1DomainReference (l1RelOrAbsPIESS $1) $1) }

unitExpression
  : Dimensionless { L1UnitExDimensionless (alexPosToSrcPoint $1) }
  | relOrAbsPath { L1UnitExRef ((\(L1RelOrAbsPath ss _ _) -> ss) $1) $1 }
  | double NamedSymbol unitExpression %prec unitExpression {%
     do
       (when (snd $2 /= "*") . fail $ "Expected * " ++ " at " ++ (show $3))
       return $ L1UnitScalarMup (twoPosToSpan (fst $1) (l1UnitExSS $3)) (snd $1) $3
                                                           }
  | unitExpression NamedSymbol unitExprEnding {%
     case $3 of
       (Left ex) | snd $2 == "*" -> return $ L1UnitExTimes (twoPosToSpan (l1UnitExSS $1) (l1UnitExSS ex)) $1 ex
       (Right (ss, d)) | snd $2 == "**" -> return $ L1UnitPow (twoPosToSpan (l1UnitExSS $1) ss) $1 d
       otherwise -> happyError (TokNamedSymbol $2)
                                              }
  | scopedId { L1UnitScopedVar (l1ScopedIdSS $1) $1 }

unitExprEnding : double %prec highestSep { Right (fst $1, snd $1) }
               | unitExpression %prec unitExprEnding { Left $1 }
double : SignedInt { (alexPosToSrcPoint $ fst $1, fromIntegral (snd $1)) }
       | Int { (alexPosToSrcPoint $ fst $1, fromIntegral (snd $1)) }
       | Real { (alexPosToSrcPoint $ fst $1, snd $1) }
integer : SignedInt { (alexPosToSrcPoint $ fst $1, fromIntegral (snd $1)) }
        | Int { (alexPosToSrcPoint $ fst $1, fromIntegral (snd $1)) }

expression
  :: { L1Expression }
  : expression applyOrWhereOrAs %prec expressionCombine { $2 $1 }
  | relOrAbsPathPossiblyIntEnd %prec expressionCombine {
      L1ExReference (l1RelOrAbsPIESS $1) $1
    }
  | scopedId %prec expressionCombine { L1ExBoundVariable (l1ScopedIdSS $1) $1 }
  | OpenBracket expression CloseBracket { $2 }
  | R maybe(bracketedUnits) PathSep double %prec expressionCombine {
      L1ExLiteralReal (twoPosToSpan (alexPosToSrcPoint $1) (fst $4))
                      (fromMaybe (L1UnitExDimensionless (alexPosToSrcPoint $1)) $2) (snd $4) }
  | OpenProductBracket sepBy(labelledExpression,Comma) CloseProductBracket %prec expressionCombine {
      L1ExMkProduct (twoPosToSpan (alexPosToSrcPoint $1) (alexPosToSrcPoint $3)) $2
     }
  | Lookup relOrAbsPathPossiblyIntEnd %prec expressionCombine { 
      L1ExProject (twoPosToSpan (alexPosToSrcPoint $1)
                  (l1RelOrAbsPIESS $2)) $2
     }
  | Append relOrAbsPathPossiblyIntEnd %prec expressionCombine {
      L1ExAppend (twoPosToSpan (alexPosToSrcPoint $1)
                               (l1RelOrAbsPIESS $2)) $2
     }
  | ForwardSlash many(scopedId) RightArrow expression %prec expressionCombine {
      let ss = twoPosToSpan (alexPosToSrcPoint $1) (l1ExSS $4)
        in foldl' (\ex sv -> L1ExLambda ss sv ex) $4 $2
    }
  | startBlock(Case) expression Of many(expressionCase) closeBlock {
      L1ExCase (twoPosToSpan $1 $5) $2 $4
    }
  | String {
      L1ExString (alexPosToSrcPoint $ fst $1) (snd $1)
    }
  | expression PathSep domainType %prec expressionSig {
      L1ExSignature (twoPosToSpan (l1ExSS $1) (l1DomainTypeSS $3)) $1 $3
    }

expressionCase : startBlockRelOrAbsPathPossiblyIntEnd RightArrow expression closeBlock {
    ($1, $3)
  }

applyOrWhereOrAs : Where namespaceContents %prec expressionCombine {
    \expr -> L1ExLet (twoPosToSpan (l1ExSS expr) (alexPosToSrcPoint $1)) expr $2 }
  | expression %prec expressionCombine { \expr -> L1ExApply (twoPosToSpan (l1ExSS expr) (l1ExSS $1)) expr $1 }
  | As relOrAbsPathPossiblyIntEnd %prec expressionCombine { \expr -> L1ExMkUnion (twoPosToSpan (l1ExSS expr) (l1RelOrAbsPIESS $2)) $2 expr }

unitDefinition :: { L1UnitDefinition }
  : Newbase { L1UnitDefNewBase (alexPosToSrcPoint $1) }
  | unitExpression { L1UnitDefUnitExpr (l1UnitExSS $1) $1 }

labelledExpression
  : relOrAbsPathPossiblyIntEnd Colon expression { ($1, $3) }

startBlock(t) : t {% do
                      let (AlexPn _ _ _ col) = $1
                      alexPushBlockIndent (col + 1)
                      return $ alexPosToSrcPoint $1
                  }
startBlockRelOrAbsPathPossiblyIntEnd
  : relOrAbsPathPossiblyIntEnd {%
      do
        let col = srcStartColumn (l1RelOrAbsPIESS $1)
        alexPushBlockIndent (col + 1)
        return $1
                               }
closeBlock : CloseBlock { alexPosToSrcPoint $1 }

maybe(x) : x           { Just $1 }
         | {- empty -} { Nothing }

many(x) : manyRev(x) { reverse $1 }
manyRev(x) : manyRev(x) x { $2:$1 }
           | {- empty -} %prec lowerSep { [] }

sepBy(x,sep) : orEmpty(sepBy1(x,sep)) { $1 }
sepBy1(x,sep) : sepBy1Rev(x,sep) { reverse ($1) }
sepBy1Rev(x,sep) : sepBy1Rev(x,sep) sep x %prec highestSep { $3:$1 }
                 | x %prec lowerSep { [$1] }
orEmpty(x) : x %prec highestEmpty { $1 }
           | {- empty -} %prec lowerEmpty { [] }
orEmptyNSContents(x) : x { $1 }
                     | {- empty -} { L1NamespaceContents [] }

{
twoPosToSpan :: SrcSpan -> SrcSpan -> SrcSpan
twoPosToSpan (SrcSpan { srcFile = f, srcStartRow = r1, srcStartColumn = c1 }) (SrcSpan { srcEndRow = r2, srcEndColumn = c2 }) =
  SrcSpan { srcFile = f, srcStartRow = r1, srcStartColumn = c1, srcEndRow = r2, srcEndColumn = c2 }

happyError failTok = do
  (pn, _, _) <- alexGetInput
  fail $ "Parse error; unexpected token " ++ (show failTok) ++ ", at " ++ (show pn)

parseFieldML :: String -> LBS.ByteString -> Either String L1NamespaceContents
parseFieldML srcFile bs = runAlex srcFile bs happyParseFieldML

alexPosToSrcPoint (AlexPn fn _ row col) = SrcSpan { srcFile = fn,
                                                    srcStartRow = row,
                                                    srcStartColumn = col,
                                                    srcEndRow = row,
                                                    srcEndColumn = col
  }
}
