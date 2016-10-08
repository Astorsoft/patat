--------------------------------------------------------------------------------
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell            #-}
module Patat.Theme
    ( Theme (..)
    , defaultTheme
    , style
    , Style (..)
    ) where


--------------------------------------------------------------------------------
import           Control.Monad          (mplus)
import qualified Data.Aeson             as A
import qualified Data.Aeson.TH.Extended as A
import           Data.List              (intercalate)
import qualified Data.Map               as M
import           Data.Maybe             (mapMaybe, maybeToList)
import           Data.Monoid            (Monoid (..), (<>))
import qualified System.Console.ANSI    as Ansi
import           Prelude


--------------------------------------------------------------------------------
data Theme = Theme
    { themeEmph   :: !(Maybe Style)
    , themeStrong :: !(Maybe Style)
    , themeCode   :: !(Maybe Style)
    } deriving (Show)


--------------------------------------------------------------------------------
instance Monoid Theme where
    mempty = Theme Nothing Nothing Nothing

    mappend l r = Theme
        { themeEmph   = themeEmph   l `mplus` themeEmph   r
        , themeStrong = themeStrong l `mplus` themeStrong r
        , themeCode   = themeCode   l `mplus` themeCode   r
        }


--------------------------------------------------------------------------------
defaultTheme :: Theme
defaultTheme = Theme
    { themeEmph   = dull Ansi.Green
    , themeStrong = dull Ansi.Red <> bold
    , themeCode   = dull Ansi.White <> ondull Ansi.Black
    }
  where
    dull   c = Just $ Style [Ansi.SetColor Ansi.Foreground Ansi.Dull c]
    ondull c = Just $ Style [Ansi.SetColor Ansi.Background Ansi.Dull c]
    bold     = Just $ Style [Ansi.SetConsoleIntensity Ansi.BoldIntensity]


--------------------------------------------------------------------------------
-- | Easier accessor
style :: (Theme -> Maybe Style) -> Theme -> [Ansi.SGR]
style f = maybe [] unStyle . f


--------------------------------------------------------------------------------
newtype Style = Style {unStyle :: [Ansi.SGR]}
    deriving (Monoid, Show)


--------------------------------------------------------------------------------
instance A.ToJSON Style where
    toJSON = A.toJSON . mapMaybe nameForSGR . unStyle


--------------------------------------------------------------------------------
instance A.FromJSON Style where
    parseJSON val = do
        names <- A.parseJSON val
        sgrs  <- mapM toSgr names
        return $! Style sgrs
      where
        toSgr name = case M.lookup name sgrsByName of
            Just sgr -> return sgr
            Nothing  -> fail $!
                "Unknown style: " ++ show name ++ ". Known styles are: " ++
                intercalate ", " (map show $ M.keys sgrsByName)


--------------------------------------------------------------------------------
nameForSGR :: Ansi.SGR -> Maybe String
nameForSGR (Ansi.SetColor layer intensity color) = Just $
    (case layer of
        Ansi.Foreground -> ""
        Ansi.Background -> "on") ++
    (case intensity of
        Ansi.Dull  -> "dull"
        Ansi.Vivid -> "vivid") ++
    (case color of
        Ansi.Black   -> "black"
        Ansi.Red     -> "red"
        Ansi.Green   -> "green"
        Ansi.Yellow  -> "yellow"
        Ansi.Blue    -> "blue"
        Ansi.Magenta -> "magenta"
        Ansi.Cyan    -> "cyan"
        Ansi.White   -> "white")

nameForSGR (Ansi.SetUnderlining Ansi.SingleUnderline) = Just "underline"

nameForSGR (Ansi.SetConsoleIntensity Ansi.BoldIntensity) = Just "bold"

nameForSGR _ = Nothing


--------------------------------------------------------------------------------
sgrsByName :: M.Map String Ansi.SGR
sgrsByName = M.fromList
    [ (name, sgr)
    | sgr  <- knownSgrs
    , name <- maybeToList (nameForSGR sgr)
    ]
  where
    -- | It doesn't really matter if we generate "too much" SGRs here since
    -- 'nameForSGR' will only pick the ones we support.
    knownSgrs =
        [ Ansi.SetColor l i c
        | l <- [minBound .. maxBound]
        , i <- [minBound .. maxBound]
        , c <- [minBound .. maxBound]
        ] ++
        [Ansi.SetUnderlining      u | u <- [minBound .. maxBound]] ++
        [Ansi.SetConsoleIntensity c | c <- [minBound .. maxBound]]


--------------------------------------------------------------------------------
$(A.deriveJSON A.dropPrefixOptions ''Theme)
