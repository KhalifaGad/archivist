-- check.hs -- Lesson 13 (capstone) verification
-- Checks two things:
--   1. cabal test is still green
--   2. cabal run archivist-demo produces narrative output covering
--      the happy verify path AND the tamper-detection path.

import Data.List (isInfixOf)
import System.Directory (setCurrentDirectory, doesFileExist)
import System.Exit (ExitCode (..), exitFailure)
import System.Process (rawSystem, readProcessWithExitCode)
import Control.Monad (unless)

main :: IO ()
main = do
  setCurrentDirectory "../../.."

  putStrLn "Step 1: cabal test"
  code <- rawSystem "cabal" ["test", "--test-show-details=streaming"]
  case code of
    ExitSuccess -> putStrLn "  \x2713 cabal test green."
    _           -> do
      putStrLn "  \x2717 cabal test failed. Read the output above."
      exitFailure

  putStrLn "\nStep 2: cabal run archivist-demo (capturing output)"
  (rcode, out, err) <-
    readProcessWithExitCode "cabal" ["run", "-v0", "archivist-demo"] ""
  case rcode of
    ExitFailure _ -> do
      putStrLn ("  \x2717 archivist-demo failed to run:\n" ++ err)
      exitFailure
    ExitSuccess -> do
      let needles =
            [ "verify = True"
            , "verify = False"
            ]
      mapM_ (\n ->
        if n `isInfixOf` out
          then putStrLn ("  \x2713 demo output mentions " ++ show n)
          else do
            putStrLn ("  \x2717 demo output is missing " ++ show n)
            putStrLn ("    Got:\n" ++ out)
            exitFailure) needles

  putStrLn "\nStep 3: README.md and REFLECTION.md exist at repo root"
  haveReadme  <- doesFileExist "README.md"
  haveReflect <- doesFileExist "REFLECTION.md"
  unless haveReadme $ do
    putStrLn "  \x2717 README.md missing at repo root."
    exitFailure
  unless haveReflect $ do
    putStrLn "  \x2717 REFLECTION.md missing at repo root."
    exitFailure
  putStrLn "  \x2713 README.md and REFLECTION.md present."

  putStrLn "\nPASS \x2713 -- Stage 1 complete."
