--------------------------------------------------------------------------------
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RecordWildCards            #-}
module Patat.Presentation.Display
    ( displayPresentation
    , dumpPresentation
    ) where


--------------------------------------------------------------------------------
import           Data.Data.Extended               (grecQ)
import           Data.List                        (intersperse)
import           Data.Monoid                      (mconcat, (<>))
import           Patat.Presentation.Display.Table
import           Patat.Presentation.Internal
import           Patat.PrettyPrint                ((<$$>), (<+>))
import qualified Patat.PrettyPrint                as PP
import           Prelude
import qualified System.Console.ANSI              as Ansi
import qualified System.Console.Terminal.Size     as Terminal
import qualified Text.Pandoc.Extended             as Pandoc


--------------------------------------------------------------------------------
displayPresentation :: Presentation -> IO ()
displayPresentation Presentation {..} = do
    Ansi.clearScreen
    Ansi.setCursorPosition 0 0

    -- Get terminal width/title
    mbWindow <- Terminal.size
    let termWidth   = maybe 72 Terminal.width  mbWindow
        termHeight  = maybe 24 Terminal.height mbWindow
        title       = PP.toString (prettyInlines pTitle)
        titleWidth  = length title
        titleOffset = (termWidth - titleWidth) `div` 2

    Ansi.setCursorColumn titleOffset
    PP.putDoc $ PP.dullyellow $ PP.string title
    putStrLn ""
    putStrLn ""

    let slide = case drop pActiveSlide pSlides of
            []      -> mempty
            (s : _) -> s

    PP.putDoc $ prettySlide slide
    putStrLn ""

    let active      = show (pActiveSlide + 1) ++ " / " ++ show (length pSlides)
        activeWidth = length active

    Ansi.setCursorPosition (termHeight - 2) 0
    PP.putDoc $ " " <> PP.dullyellow (prettyInlines pAuthor)
    Ansi.setCursorColumn (termWidth - activeWidth - 1)
    PP.putDoc $ PP.dullyellow $ PP.string active
    putStrLn ""


--------------------------------------------------------------------------------
dumpPresentation :: Presentation -> IO ()
dumpPresentation =
    PP.putDoc . PP.vcat . intersperse "----------" . map prettySlide . pSlides


--------------------------------------------------------------------------------
prettySlide :: Slide -> PP.Doc
prettySlide slide@(Slide blocks) =
    prettyBlocks blocks <>
    case prettyReferences slide of
        []   -> mempty
        refs -> PP.newline <> PP.vcat refs


--------------------------------------------------------------------------------
prettyBlock :: Pandoc.Block -> PP.Doc

prettyBlock (Pandoc.Plain inlines) = prettyInlines inlines

prettyBlock (Pandoc.Para inlines) = prettyInlines inlines <> PP.newline

prettyBlock (Pandoc.Header i _ inlines) =
    PP.dullblue (PP.string (replicate i '#') <+> prettyInlines inlines) <>
    PP.newline

prettyBlock (Pandoc.CodeBlock _ txt) = PP.vcat
    [ let ind = PP.NotTrimmable "   " in
      PP.indent ind ind $ PP.ondullblack $ PP.dullwhite $ PP.string line
    | line <- blockified txt
    ] <> PP.newline
  where
    blockified str =
        let ls       = lines str
            longest  = foldr max 0 (map length ls)
            extend l = " " ++ l ++ replicate (longest - length l) ' ' ++ " " in
        map extend $ [""] ++ ls ++ [""]

prettyBlock (Pandoc.BulletList bss) = PP.vcat
    [ PP.indent
        (PP.NotTrimmable $ PP.dullmagenta "  - ")
        (PP.Trimmable "    ")
        (prettyBlocks bs)
    | bs <- bss
    ] <> PP.newline

prettyBlock (Pandoc.OrderedList _ bss) = PP.vcat
    [ PP.indent
        (PP.NotTrimmable $ PP.dullmagenta $ PP.string prefix)
        (PP.Trimmable "    ")
        (prettyBlocks bs)
    | (prefix, bs) <- zip padded bss
    ] <> PP.newline
  where
    padded  = [n ++ replicate (4 - length n) ' ' | n <- numbers]
    numbers =
        [ show i ++ "."
        | i <- [1 .. length bss]
        ]

prettyBlock (Pandoc.RawBlock _ t) = PP.string t <> PP.newline

prettyBlock Pandoc.HorizontalRule = "---"

prettyBlock (Pandoc.BlockQuote bs) =
    let quote = PP.NotTrimmable (PP.dullgreen "> ") in
    PP.indent quote quote (prettyBlocks bs)

prettyBlock (Pandoc.Table caption aligns _ headers rows) = prettyTable Table
    { tCaption = prettyInlines caption
    , tAligns  = map align aligns
    , tHeaders = map prettyBlocks headers
    , tRows    = map (map prettyBlocks) rows
    }
  where
    align Pandoc.AlignLeft    = PP.AlignLeft
    align Pandoc.AlignCenter  = PP.AlignCenter
    align Pandoc.AlignDefault = PP.AlignLeft
    align Pandoc.AlignRight   = PP.AlignRight

prettyBlock (Pandoc.Div _attrs blocks) = prettyBlocks blocks

prettyBlock (Pandoc.DefinitionList terms) =
    PP.vcat $ map prettyDefinition terms
  where
    prettyDefinition (term, definitions) =
        PP.dullblue (prettyInlines term) <$$> PP.newline <> PP.vcat
        [ PP.indent
            (PP.NotTrimmable (PP.dullmagenta ":   "))
            (PP.Trimmable "    ") $
            prettyBlocks (Pandoc.plainToPara definition)
        | definition <- definitions
        ]

prettyBlock Pandoc.Null = mempty


--------------------------------------------------------------------------------
prettyBlocks :: [Pandoc.Block] -> PP.Doc
prettyBlocks = PP.vcat . map prettyBlock


--------------------------------------------------------------------------------
prettyInline :: Pandoc.Inline -> PP.Doc

prettyInline Pandoc.Space = PP.space

prettyInline (Pandoc.Str str) = PP.string str

prettyInline (Pandoc.Emph inlines) =
    PP.dullgreen $ prettyInlines inlines

prettyInline (Pandoc.Strong inlines) =
    PP.dullred $ PP.bold $ prettyInlines inlines

prettyInline (Pandoc.Code _ txt) =
    PP.ondullblack $ PP.dullwhite $ " " <> PP.string txt <> " "

prettyInline link@(Pandoc.Link _attrs text (target, _title))
    | isReferenceLink link =
        "[" <> PP.dullcyan (prettyInlines text) <> "]"
    | otherwise =
        "<" <> PP.dullcyan (PP.underline $ PP.string target) <> ">"

prettyInline Pandoc.SoftBreak = PP.newline

prettyInline Pandoc.LineBreak = PP.newline

prettyInline (Pandoc.Strikeout t) =
    "~~" <> PP.ondullred (prettyInlines t) <> "~~"

prettyInline (Pandoc.Quoted Pandoc.SingleQuote t) =
    "'" <> PP.dullgreen (prettyInlines t) <> "'"
prettyInline (Pandoc.Quoted Pandoc.DoubleQuote t) =
    "'" <> PP.dullgreen (prettyInlines t) <> "'"

prettyInline (Pandoc.Math _ t) = PP.dullgreen (PP.string t)

prettyInline (Pandoc.Image _ _ (tit, src)) =
    "![" <> PP.dullgreen (PP.string tit) <> "](" <>
    PP.dullcyan (PP.underline (PP.string src)) <> ")"

-- These elements aren't really supported.
prettyInline (Pandoc.Cite      _ t) = prettyInlines t
prettyInline (Pandoc.Span      _ t) = prettyInlines t
prettyInline (Pandoc.RawInline _ t) = PP.string t
prettyInline (Pandoc.Note        t) = prettyBlocks t
prettyInline (Pandoc.Superscript t) = prettyInlines t
prettyInline (Pandoc.Subscript   t) = prettyInlines t
prettyInline (Pandoc.SmallCaps   t) = prettyInlines t
-- prettyInline unsupported = PP.ondullred $ PP.string $ show unsupported


--------------------------------------------------------------------------------
prettyInlines :: [Pandoc.Inline] -> PP.Doc
prettyInlines = mconcat . map prettyInline


--------------------------------------------------------------------------------
prettyReferences :: Slide -> [PP.Doc]
prettyReferences =
    map prettyReference . getReferences . unSlide
  where
    getReferences :: [Pandoc.Block] -> [Pandoc.Inline]
    getReferences = filter isReferenceLink . grecQ

    prettyReference :: Pandoc.Inline -> PP.Doc
    prettyReference (Pandoc.Link _attrs text (target, title)) =
        "[" <> PP.dullgreen (prettyInlines $ Pandoc.newlineToSpace text) <>
        "](" <>
        PP.dullcyan (PP.underline (PP.string target)) <>
        (if null title
            then mempty
            else PP.space <> "\"" <> PP.string title <> "\"")
        <> ")"
    prettyReference _ = mempty


--------------------------------------------------------------------------------
isReferenceLink :: Pandoc.Inline -> Bool
isReferenceLink (Pandoc.Link _attrs text (target, _)) =
    [Pandoc.Str target] /= text
isReferenceLink _ = False
