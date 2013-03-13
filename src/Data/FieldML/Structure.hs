{-# LANGUAGE DeriveDataTypeable, GADTs, StandaloneDeriving  #-}
module Data.FieldML.Structure
where

import qualified Data.Map as M
import qualified Data.ByteString.Char8 as BS
import Data.Typeable
import Data.Data
import qualified Data.FieldML.Level1Structure as L1
import Data.FieldML.Level1Structure (SrcSpan)

newtype NamespaceID = NamespaceID Integer deriving (Eq, Ord, Show, Typeable, Data)
newtype NewDomainID = NewDomainID Integer deriving (Eq, Ord, Show, Typeable, Data)
newtype NamedValueID = NamedValueID Integer deriving (Eq, Ord, Show, Typeable, Data)
newtype DomainClassID = DomainClassID Integer deriving (Eq, Ord, Show, Typeable, Data)
newtype ScopedVariable = ScopedVariable Integer deriving (Eq, Ord, Show, Typeable, Data)
newtype UnitID = UnitID Integer deriving (Eq, Ord, Show, Typeable, Data)

data Model = Model {
  nextNSID :: NamespaceID,                      -- ^ The next NamespaceID to allocate.
  nextNewDomain :: NewDomainID,                 -- ^ The next NewDomainID to allocate.
  nextNamedValue :: NamedValueID,               -- ^ The next NamedValueID to allocate.
  nextDomainClass :: DomainClassID,             -- ^ The next DomainClassID to allocate.
  nextUnit :: UnitID,                           -- ^ The next UnitID to allocate.
  nextScopedVariable :: ScopedVariable,         -- ^ The next ScopedVariable to allocate.
  toplevelNamespace :: NamespaceID,             -- ^ The top-level namespace.
  allNamespaces :: M.Map NamespaceID Namespace, -- ^ All namespaces in the model.
  allNewDomains :: M.Map NewDomainID NewDomain, -- ^ All NewDomains in the model.
  allDomainClasses :: M.Map DomainClassID DomainClass, -- ^ All domainclasses in the model.
  allNamedValues :: M.Map NamedValueID NamedValue, -- ^ All NamedValues in the model.
  allUnits :: M.Map UnitID Unit,                -- ^ All units in the model.
  instancePool :: M.Map (DomainClassID, [DomainType]) Instance, -- ^ All domain instance definitions.
  modelAssertions :: [Expression],              -- ^ A list of assertions that hold in this model.
  modelForeignNamespaces :: M.Map (BS.ByteString, NamespaceID) NamespaceID, -- ^ Foreign => Local namespace map
  modelForeignDomains :: M.Map (BS.ByteString, NewDomainID) NewDomainID, -- ^ Foreign => Local domain map
  modelForeignDomainClasses :: M.Map (BS.ByteString, DomainClassID) DomainClassID, -- ^ Foreign => Local domain class map
  modelForeignValues :: M.Map (BS.ByteString, NamedValueID) NamedValueID, -- ^ Foreign => Local named value map
  modelForeignUnits :: M.Map (BS.ByteString, UnitID) UnitID -- ^ Foreign => Local units map
  } deriving (Eq, Ord, Show, Typeable)

data ELabel = ELabel { labelEnsemble :: NamespaceID,
                       labelValue :: Integer
                     } deriving (Eq, Ord, Show, Typeable, Data)

data NewDomain = CloneDomain SrcSpan CloneAnnotation DomainType | -- ^ Clone another domain.
                 BuiltinDomain SrcSpan                            -- ^ A built-in domain.
                           deriving (Eq, Ord, Show, Typeable)

domainSrcSpan :: NewDomain a -> SrcSpan
domainSrcSpan (CloneDomain ss _ _ ) = ss
domainSrcSpan (BuiltinDomain ss) = ss

-- | Clone annotation containss information which isn't always strictly needed
--   interpret FieldML, but provides useful semantic information to some
--   applications.
data CloneAnnotation = NormalClone |             -- ^ A straight clone.
                       SubsetClone Expression |  -- ^ Clone, taking subset. Expression must be a field from the original domain onto boolean.
                       ConnectClone [Expression] -- ^ Clone, changing connectivity. Expressions must be a field from the original domain onto some other domain.
                             deriving (Eq, Ord, Show, Typeable)

data DomainExpression =
  UseNewDomain NewDomainID | -- ^ Refer to a defined domain
  UseRealUnits UnitExpr | -- ^ Refer to a builtin Real with units domain.
  ApplyDomain DomainExpression ScopedVariable DomainExpression | -- ^ Apply one domain variable
  DomainVariable ScopedVariable | -- ^ Refer to a domain variable.
  ProductDomain (M.Map ELabel DomainExpression) | -- ^ Product domain.
  DisjointUnion (M.Map ELabel DomainExpression) | -- ^ Disjoint union.
  FieldSignature DomainExpression DomainExpression | -- ^ Field signature.
  -- | Completely evaluate a domainfunction. Negative values reference class arguments.
  EvaluateDomainFunction DomainClassID Int [DomainExpression]
  deriving (Eq, Ord, Show, Typeable)

data DomainType = DomainType SrcSpan DomainHead DomainExpression deriving (Eq, Ord, Show, Typeable)

data DomainHead = DomainHead [DomainClassRelation] deriving (Eq, Ord, Show, Typeable)

data DomainClassRelation =
  DomainClassRelation DomainClassID [DomainType] |
  DomainClassEqual DomainType DomainType |
  DomainUnitConstraint UnitExpr UnitExpr -- ^ A units constraint on the domain.
  deriving (Eq, Ord, Show, Typeable)

data Namespace = Namespace {
  nsSrcSpan :: SrcSpan,
  -- | All namespaces. Note that this includes entries for all domains and
  --   fields and classes, since they are also namespaces.
  nsNamespaces :: M.Map BS.ByteString NamespaceID,
  -- | All domains.
  nsDomains :: M.Map BS.ByteString DomainType,
  -- | All values.
  nsValues :: M.Map BS.ByteString NamedValueID,
  -- | All classes.
  nsClasses :: M.Map BS.ByteString DomainClassID,
  -- | All labels in the namespace.
  nsLabels :: M.Map BS.ByteString ELabel,
  -- | The units in the namespace.
  nsUnits :: M.Map BS.ByteString UnitExpr,
  -- | The parent of this namespace.
  nsParent :: NamespaceID,
  -- | The number of label IDs assigned in this namespace.
  nsNextLabel :: Int
                           }
               deriving (Eq, Ord, Show, Typeable)

-- | One entry for each parameter, parameter is ClassKind [] if it doesn't itself have parameters.
data ClassKind = ClassKind [ClassKind] deriving (Eq, Ord, Show, Data, Typeable)

data DomainClass = DomainClass {
  classSrcSpan :: SrcSpan,
  -- | The number of parameters this class takes.
  classKind :: ClassKind,
  -- | The domain functions defined by instances of this class. The second
  --   argument is the number of arguments.
  classDomainFunctions :: M.Map BS.ByteString Int,
  -- | The values defined by instances of this class. ScopedVariables 0..(n-1) refer to the arguments.
  classValues :: M.Map BS.ByteString (Int, DomainType)
  } deriving (Eq, Ord, Show, Typeable)

data Instance forward = Instance {
  instanceSrcSpan :: SrcSpan,
  -- | Instances with higher numerical precedence values override those with lower values.
  instancePrecedence :: Integer,
  -- | Any domain functions defined on this instance (must correspond to class domainfunctions).
  instanceDomainFunctions :: M.Map Int DomainType,
  -- | Assertions involving any values in scope.
  instanceAssertions :: [Expression]
  } deriving (Eq, Ord, Show, Typeable)

data NamedValue = NamedValue {
  namedValueSrcSpan :: SrcSpan,
  -- | Only relevant for field value instances when applied inline. Fields with
  --   higher numerical precedence values are applied first.
  namedValuePrecedence :: Integer
  } | FFINamedValue { binvModule :: BS.ByteString, -- ^ The module containing the FFI value.
                      binvBase :: BS.ByteString    -- ^ The base name of the FFI value.
                    } -- ^ A foreign named value.
                deriving (Eq, Ord, Data, Show, Typeable)

data Expression = Apply SrcSpan Expression Expression | -- ^ Apply an expression to a field expression
                  NamedValueRef SrcSpan NamedValueID | -- ^ Reference a named field.
                  LabelRef SrcSpan ELabel     | -- ^ Reference a label.
                  LiteralReal SrcSpan UnitExpr Double | -- ^ Reference a real value.
                  BoundVar SrcSpan ScopedVariable | -- ^ Reference a bound variable.
                  MkProduct SrcSpan (M.Map ELabel Expression) | -- ^ Construct a product.
                  MkUnion SrcSpan ELabel | -- ^ Make a field that constructs a union.
                  Project SrcSpan ELabel | -- ^ Make a field that deconstructs a union.
                  Append SrcSpan ELabel  | -- ^ Make a field that adds to a product.
                  Lambda SrcSpan ScopedVariable Expression | -- ^ Define a lambda field.
                  -- | Split on values of the first Expression. The final Expression
                  --   specifies what to do if nothing matches.
                  Case SrcSpan Expression (M.Map ELabel Expression)
                    deriving (Eq, Ord, Show, Typeable)

-- | Represents an expression on units.
data UnitExpr = 
  UnitDimensionless SrcSpan |             -- ^ Refer to dimensionless
  UnitRef SrcSpan UnitID |                -- ^ Refer to a unit defined elsewhere.
  UnitTimes SrcSpan UnitExpr UnitExpr |   -- ^ Multiply two units. E.g. Times metre second = metre.second
  UnitPow SrcSpan UnitExpr Double |       -- ^ Raise a unit to a power. e.g. Pow second -1 = second^-1
  UnitScalarMup SrcSpan Double UnitExpr | -- ^ Multiply a unit by a scalar. E.g. ScalarMup 1E-3 metre = millimetre
  UnitScopedVar SrcSpan ScopedVariable    -- ^ Refer to a scoped variable.
  deriving (Eq, Ord, Show, Typeable)

-- | Represents a unit that has been defined.
data Unit = NewBaseUnit { baseUnitSrcSpan :: SrcSpan }           -- ^ Defines a new builtin unit.
              deriving (Eq, Ord, Data, Show, Typeable)