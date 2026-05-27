-- check.hs — Lesson 1 verification
-- Read this BEFORE writing Archivist.hs. It's the spec.

import Archivist
import System.Exit (exitFailure)

main :: IO ()
main = do
  let e1 = mkEvent "order-placed"     "evt-1" "2024-01-01T10:00:00Z"
      e2 = mkEvent "payment-received" "evt-2" "2024-01-01T10:05:00Z"

  -- Accessors
  check "payload extracts the first field"    (payload e1   == "order-placed")
  check "eventId extracts the second field"   (eventId e1   == "evt-1")
  check "timestamp extracts the third field"  (timestamp e1 == "2024-01-01T10:00:00Z")

  -- Empty log
  let log0 :: Log
      log0 = []

  -- Single append
  let log1 = appendEvent e1 log0
  check "appending to empty log gives a one-element log" (log1 == [e1])

  -- Order preservation — the append-only invariant in miniature
  let log2 = appendEvent e2 log1
  check "appendEvent preserves order: oldest first, newest last"
        (log2 == [e1, e2])

  -- A few more, just to be sure ordering isn't accidental
  let log3 = appendEvent (mkEvent "p3" "evt-3" "t3") log2
      log4 = appendEvent (mkEvent "p4" "evt-4" "t4") log3
  check "ordering is stable across multiple appends"
        (map eventId log4 == ["evt-1", "evt-2", "evt-3", "evt-4"])

  putStrLn "PASS \x2713 -- Lesson 1 complete."

check :: String -> Bool -> IO ()
check desc True  = putStrLn ("  \x2713 " ++ desc)
check desc False = do
  putStrLn ("  \x2717 " ++ desc)
  exitFailure
