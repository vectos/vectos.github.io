--------------------------------------------------------------------------------
{-# LANGUAGE OverloadedStrings #-}
import           Data.Monoid (mappend, (<>))
import           Hakyll


--------------------------------------------------------------------------------
main :: IO ()
main = hakyll $ do
    match "img/**" $ do
        route   idRoute
        compile copyFileCompiler

    match "css/*" $ do
        route   idRoute
        compile compressCssCompiler

    match "js/*" $ do
        route   idRoute
        compile copyFileCompiler

    match "posts/*" $ do
        route $ setExtension "html"
        compile $
          pandocCompiler
            >>= loadAndApplyTemplate "templates/post.html"    (postCtx)
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    match "portfolio/*" $ do
        route $ setExtension "html"
        compile $ do
          posts <- recentFirst =<< loadAll "posts/*"
          let indexCtx = listField "posts" postCtx (return posts) `mappend` defaultContext

          pandocCompiler
            >>= loadAndApplyTemplate "templates/portfolio-item.html" (postCtx `mappend` indexCtx)
            >>= loadAndApplyTemplate "templates/default.html" postCtx
            >>= relativizeUrls

    match "index.html" $ do
        route idRoute
        compile $ do
            posts <- recentFirst =<< loadAll "posts/*"
            portfolio <- loadAll "portfolio/*"
            let indexCtx =
                    listField "posts" postCtx (return posts) `mappend`
                    listField "portfolio" postCtx (return portfolio) `mappend`
                    constField "title" "Home"                `mappend`
                    defaultContext

            getResourceBody
                >>= applyAsTemplate indexCtx
                >>= loadAndApplyTemplate "templates/default.html" indexCtx
                >>= relativizeUrls

    match "templates/*" $ compile templateBodyCompiler


--------------------------------------------------------------------------------
postCtx :: Context String
postCtx = dateField "date" "%B %e, %Y" <> defaultContext
