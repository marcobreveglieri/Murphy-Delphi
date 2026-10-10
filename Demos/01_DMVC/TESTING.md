# Testing guide

This guide walks through every feature of the DMVC chaos demo. Each test states its goal, the steps to perform, and the expected result. You can run the tests from the dashboard, with `curl`, or both. For an overview of the demo and of its design, see the [README](README.md).

The tests build on each other. Run them in order, and reset the settings (see [Reset the settings](#reset-the-settings)) whenever a test starts from the defaults.

## Before you start

- Build the demo as described in the [README](README.md#build-and-run), start `Murphy.Demos.DMVC.exe`, and keep its console visible: the log is part of the expected results.
- Open <http://localhost:8080/> in a browser.
- The `curl` commands use the syntax of a POSIX shell (Git Bash, WSL, macOS, Linux). From `cmd` or PowerShell, call `curl.exe` and adapt the quoting of the JSON bodies, or change the settings from the dashboard instead.
- Injected failures are random: an injection rate of 30% gives about 3 failures in 10 requests, not exactly 3. Where a test needs certainty it uses a rate of 0% or 100%.

### Reset the settings

This command restores the settings the server has at startup:

```sh
curl -X PUT http://localhost:8080/chaos -H "Content-Type: application/json" -d '{
  "enabled": true, "blastRadius": "marked",
  "targets": {
    "inbound": { "faultRate": 0.1, "latencyRate": 0.2, "latencyMinMs": 200, "latencyMaxMs": 800 },
    "rates": { "faultRate": 0.2, "latencyRate": 0.2, "latencyMinMs": 1500, "latencyMaxMs": 2500 } } }'
```

After you change the `rates` target, wait at least 5 seconds before the next test. An open circuit needs that long to try the service again.

## 1. Startup and dashboard

**Goal**: the server starts and the dashboard reads the settings.

1. Start the server.
2. Open <http://localhost:8080/>.

**Expected**

- The console prints `Dashboard: http://localhost:8080/` and `Press ENTER to stop the server`.
- The dashboard shows the two lanes, *Normal traffic* and *Test traffic*, and the chaos settings: *Chaos enabled* on, blast radius *Marked requests*, *Incoming requests* at 10% / 20% / 200-800 ms, *Exchange rates service* at 20% / 20% / 1500-2500 ms.
- The circuit card says *No price requested yet*.

## 2. The API without chaos

**Goal**: the endpoints work, and an unmarked request receives no chaos.

```sh
curl -i http://localhost:8080/api/products
curl http://localhost:8080/api/products/3/price/usd
curl -w " [%{http_code}]\n" http://localhost:8080/api/products/9/price/usd
curl -w " [%{http_code}]\n" http://localhost:8080/api/products/1/price/xyz
```

**Expected**

- The product list (4 products) with status 200 and no `X-Chaos-Injected` header.
- A price such as `{"productId":3,...,"currency":"USD","rate":1.0849,"price":21.59,"rateSource":"live","attempts":1,"circuit":"Closed"}`. The rate changes a little at every call.
- Status 404 for the unknown product and for the unknown currency.

## 3. The blast radius: marked requests only

**Goal**: only the requests with the `X-Chaos: on` header receive chaos.

1. On the dashboard, click **Start traffic** and wait about 20 seconds.
2. Or, with `curl`, send the same request with and without the header:

   ```sh
   for i in $(seq 20); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/api/products; done; echo
   for i in $(seq 20); do curl -s -o /dev/null -D - -H "X-Chaos: on" http://localhost:8080/api/products | grep -iE "^HTTP|^X-Chaos-Injected"; done
   ```

**Expected**

- *Normal traffic* keeps 100% success and a p95 latency of about 100 ms. The only exception is when the test traffic opens the circuit, which is rare at the default rates: see test 9.
- *Test traffic* shows some errors (red markers, status 503) and some tall columns (200-800 ms of injected latency). Price requests now and then need more than one attempt.
- With `curl`, every unmarked request returns 200. About 10% of the marked ones return 503 with `X-Chaos-Injected: fault`, and about 20% carry `X-Chaos-Injected: latency=<ms>`.
- The console logs lines such as `Chaos: fault injected into /api/products` and `Chaos: 532 ms of latency injected into /api/products`.

Leave the traffic running for the next tests.

## 4. Fault injection into the incoming requests

**Goal**: a fault replaces the response with a 503.

1. Set *Incoming requests > Fault rate* to 100%, or:

   ```sh
   curl -X PUT http://localhost:8080/chaos -d '{"targets":{"inbound":{"faultRate":1}}}'
   curl -i -H "X-Chaos: on" http://localhost:8080/api/products
   ```

**Expected**

- Every request of the test lane fails (status 503). The *Errors* tile grows, and the log shows *Error · Fault injected into the request*.
- The `curl` response has status `503 Service Unavailable`, the header `X-Chaos-Injected: fault` and a JSON error whose message is `Chaos: fault injected`.
- The normal lane is unaffected.

Set the fault rate back to 10%.

## 5. Latency injection into the incoming requests

**Goal**: the latency delays the request, which then succeeds.

1. Set *Incoming requests*: fault rate 0%, latency rate 100%, latency 1000-1000 ms. Or:

   ```sh
   curl -X PUT http://localhost:8080/chaos -d '{"targets":{"inbound":{"faultRate":0,"latencyRate":1,"latencyMinMs":1000,"latencyMaxMs":1000}}}'
   curl -s -o /dev/null -D - -w "%{time_total} s\n" -H "X-Chaos: on" http://localhost:8080/api/products
   ```

**Expected**

- Every test request succeeds after about 1 second (`X-Chaos-Injected: latency=1000`). The test lane columns are at least 1 s tall, and its p95 latency is above 1 s.
- The normal lane stays fast.

Then set *Incoming requests* to fault 0% and latency 0%, so the next tests show only the dependency.

## 6. Fault injection into the dependency: Retry

**Goal**: the retry hides the occasional failures of the exchange rates service.

1. Set *Exchange rates service*: fault rate 30%, latency rate 0%.
2. Watch the price requests of the test lane, in the request log or with:

   ```sh
   for i in $(seq 10); do curl -s -H "X-Chaos: on" http://localhost:8080/api/products/1/price/usd; echo; done
   ```

**Expected**

- Most price requests answer `"rateSource":"live"`. Some report `"attempts":2` or `3` (log: *Live rate, retried: 2 attempts*).
- The console logs `Chaos: fault injected into the exchange rates service` for every injected fault.
- Three failures in a row open the circuit (about 3% of the requests at 30%): the next test explains what happens then.

## 7. Latency injection into the dependency: Timeout

**Goal**: the timeout cuts the slow calls short, and the retry tries again.

1. Set *Exchange rates service*: fault rate 0%, latency rate 50%, latency 1500-2500 ms.
2. Watch the price requests of the test lane.

**Expected**

- The slow attempts are abandoned after 1 second. The console logs `Chaos: 1834 ms of latency injected into the exchange rates service` followed by `Exchange rates: attempt abandoned after 1000 ms`.
- A request whose second attempt is fast answers in about 1.3 s with `"rateSource":"live","attempts":2`. On the dashboard it is a tall gray column, a success.
- No attempt lasts longer than 1 s, whatever the injected latency: the timeout bounds it. When all three attempts are slow (about 1 request in 8 at 50%), the request takes about 3.4 s, answers from the cache and opens the circuit: the next test explains it.

## 8. Circuit Breaker and Fallback

**Goal**: when the service keeps failing, the circuit opens and the fallback serves the last known rate.

1. Set *Exchange rates service*: fault rate 0%, latency rate 100%.
2. Send a few marked price requests:

   ```sh
   for i in 1 2 3; do curl -s -w "  [%{time_total} s]\n" -H "X-Chaos: on" http://localhost:8080/api/products/1/price/usd; done
   ```

3. Wait 5 seconds and send another one.
4. Set the latency rate to 0%, wait 5 seconds, and send another one.

**Expected**

- Step 2: the first request takes about 3.4 s (3 attempts, each abandoned after 1 s, with 200 ms between them) and answers `"rateSource":"cache","attempts":3,"circuit":"Open"`. The next ones answer at once from the cache, with `"attempts":1`: the open circuit does not call the service (log: *Cached rate: the circuit skipped the service*).
- The circuit card turns red: *Open: cached rates served*. Price requests appear in yellow, *Degraded*, and the console logs `Exchange rates: last USD rate served by the fallback`.
- Step 3: after the 5 s break, the circuit lets a trial call through. The trial is slow again, so the circuit opens again (about 1.2 s, `"attempts":2`, `"circuit":"Open"`).
- Step 4: the trial succeeds, the circuit closes (`"circuit":"Closed"`, card green) and the rates are live again.

## 9. Shared state widens the blast radius

**Goal**: observe how chaos limited to the test traffic still reaches the normal traffic.

1. Keep the blast radius on *Marked requests* and the traffic running.
2. Set *Exchange rates service*: fault rate 100%.

**Expected**

- The circuit opens because of the test traffic. From then on, most price requests of the **normal** lane are *Degraded* too: they get cached rates and `"circuit":"Open"`, although no chaos is injected into them. The *Degraded* tile of the normal lane grows.
- Now and then a normal request is the trial call after the 5 s break: it succeeds and closes the circuit, until the test traffic opens it again.
- The cause is the circuit breaker, which is shared by all the requests. This coupling is the kind of finding a chaos experiment exists for. A real system might accept it, or isolate the experiment, for example by giving the test traffic its own circuit breaker.

Set the fault rate back to 20% and wait for the circuit to close.

## 10. The blast radius: all requests

**Goal**: the chaos reaches the unmarked requests too.

1. Reset the settings, then select *Blast radius > All requests*. Or:

   ```sh
   curl -X PUT http://localhost:8080/chaos -d '{"blastRadius":"all"}'
   for i in $(seq 20); do curl -s -o /dev/null -w "%{http_code} " http://localhost:8080/api/products; done; echo
   ```

**Expected**

- The normal lane now looks like the test lane: errors, injected latency, retries.
- Unmarked `curl` requests return some 503s.

Select *Marked requests* again: the normal lane returns to 100% success.

## 11. The master switch

**Goal**: `MurphyChaosEnabled` turns every chaos policy off at once.

1. With the traffic running and the default settings, turn *Chaos enabled* off. Or:

   ```sh
   curl -X PUT http://localhost:8080/chaos -d '{"enabled":false}'
   ```

2. After a while, turn it on again.

**Expected**

- While the switch is off, no request receives chaos, whatever its rates and blast radius: no `X-Chaos-Injected` header and no `Chaos:` lines in the console. New columns of both lanes are short and gray.
- The other settings are kept: `GET /chaos` still shows the same rates, and when the switch is turned on again the chaos resumes with them.

## 12. Validation of the settings

**Goal**: an invalid change is rejected as a whole, and nothing changes.

```sh
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d '{"enabled":false,"targets":{"inbound":{"faultRate":1.5}}}'
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d '{"targets":{"rates":{"latencyMinMs":3000,"latencyMaxMs":1000}}}'
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d '{"targets":{"database":{"faultRate":0.5}}}'
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d '{"blastRadius":"some"}'
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d '{"enabled":"yes"}'
curl -w " [%{http_code}]\n" -X PUT http://localhost:8080/chaos -d 'hello'
curl http://localhost:8080/chaos
```

**Expected**

- Every `PUT` returns status 400 with a message: `The fault rate must be between 0 and 1`, `The latency range must satisfy 0 <= min <= max`, `Unknown chaos target "database"`, `The blast radius must be "marked" or "all"`, `"enabled" must be true or false`, `The body must be a JSON object`.
- The final `GET` shows the settings unchanged. In particular `enabled` is still `true`: the first request is rejected as a whole, even though its `enabled` value was valid.
- On the dashboard, entering a minimum latency greater than the maximum shows the error under the settings and restores the previous value.

## 13. The control endpoint answers only to the local machine

**Goal**: other machines cannot change the chaos settings.

1. Allow inbound connections to port 8080 in the Windows firewall, if needed.
2. From another machine, open `http://<server-ip>:8080/` and run:

   ```sh
   curl -i http://<server-ip>:8080/chaos
   curl -i -H "X-Forwarded-For: 127.0.0.1" http://<server-ip>:8080/chaos
   ```

**Expected**

- Both requests return `403 Forbidden` with the message `The chaos settings can be read and changed only from the local machine, not from "<client-ip>"`. The forged `X-Forwarded-For` header does not help, because the check uses the address of the connection.
- On the remote dashboard, the chaos settings are disabled and show the same message, while the traffic lanes still work.

## 14. Clean shutdown

**Goal**: the server stops cleanly, even with attempts still running in background.

1. Set *Exchange rates service* latency rate to 100% and keep the traffic running for a few seconds, so that some attempts abandoned by the timeout are still sleeping.
2. Press ENTER in the server console.

**Expected**

- The server stops. This can take up to 2.5 s, the longest injected latency, while the abandoned attempts finish.
- No `Unexpected Memory Leak` report appears (`ReportMemoryLeaksOnShutdown` is on in the demo).

## 15. Dashboard

**Goal**: the dashboard is readable and usable.

**Expected**

- Hovering over a column shows a tooltip with the latency, the outcome, the request and the detail (e.g. `Cached rate after 3 attempts · 15:35:06`).
- The legend and the request log name each outcome with an icon and a label (*✓ Success*, *◐ Degraded*, *✕ Error*), so colors are never the only clue.
- **Rate** changes the traffic of each lane (1, 2 or 4 requests per second), **Clear** empties the charts and the log, **Stop traffic** stops it.
- Both lanes use the same latency scale, so their columns can be compared.
- The page follows the light or dark theme of the operating system, and in a narrow window the panels stack in one column without horizontal scrolling.
