-- check.hs — Lesson 2 verification
-- Read this BEFORE rewriting Archivist.hs as records.

import Archivist
import System.Exit (exitFailure)

main :: IO ()
main = do
  -- Event is now a record
  let e1 = Event { payload = "order-placed",     eventId = "evt-1", timestamp = "t1" }
      e2 = Event { payload = "payment-received", eventId = "evt-2", timestamp = "t2" }

  check "Event has a payload field"    (payload e1   == "order-placed")
  check "Event has an eventId field"   (eventId e1   == "evt-1")
  check "Event has a timestamp field"  (timestamp e1 == "t1")

  -- Derived Show and Eq
  check "Event derives Show (non-empty show output)" (not (null (show e1)))
  check "Event derives Eq: equal records are =="    (e1 == e1)
  check "Event derives Eq: different records are /=" (e1 /= e2)

  -- Stream
  let s0 = emptyStream "orders"
  check "emptyStream sets the streamId"    (streamId s0 == "orders")
  check "emptyStream starts with no events" (events s0 == [])

  let s1 = appendToStream e1 s0
      s2 = appendToStream e2 s1
  check "appendToStream grows the stream by one"
        (length (events s2) == 2)
  check "appendToStream preserves order (oldest first)"
        (events s2 == [e1, e2])
  check "eventCount returns the number of events"
        (eventCount s2 == 2 && eventCount s0 == 0)

  -- record update syntax — Stream id is preserved on append
  check "appendToStream keeps the streamId"
        (streamId s2 == "orders")

  -- SealStatus exists as a sum type (foreshadowing)
  check "SealStatus has Sealed and Unsigned, and they are distinct"
        (Sealed /= Unsigned)

  -- mkEvent still works for convenience
  let e3 = mkEvent "p3" "evt-3" "t3"
  check "mkEvent still constructs Events"
        (payload e3 == "p3" && eventId e3 == "evt-3")

  putStrLn "PASS \x2713 -- Lesson 2 complete."

check :: String -> Bool -> IO ()
check desc True  = putStrLn ("  \x2713 " ++ desc)
check desc False = do
  putStrLn ("  \x2717 " ++ desc)
  exitFailure
