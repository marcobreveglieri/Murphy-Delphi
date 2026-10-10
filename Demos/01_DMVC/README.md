# Chaos engineering with DelphiMVCFramework

This demo shows how to add chaos engineering to a [DelphiMVCFramework](https://github.com/danieleteti/delphimvcframework) (DMVC) web application with Murphy. It injects faults and latency into the incoming requests and into a dependency of the application, limits the blast radius to the requests of an experiment, and lets you change every setting at runtime. A live dashboard shows how the resilience policies react.

- **Chaos on the incoming requests**: a DMVC middleware injects latency and `503 Service Unavailable` faults into the actions under `/api`.
- **Chaos on a dependency**: the client of a (simulated) exchange rates service injects faults and latency innermost, inside Timeout, Circuit Breaker, Retry and Fallback policies.
- **Blast radius**: chaos reaches only the requests marked by the `X-Chaos: on` header, or every request.
- **Runtime control**: `GET`/`PUT /chaos` reads and changes the injection rates, the latency ranges, the blast radius and the `MurphyChaosEnabled` master switch.
- **Dashboard**: two clients send the same traffic, one marked and one not, and the page shows the outcome and the latency of every request.

To test every feature step by step, see the [testing guide](TESTING.md).

## Requirements

- Delphi 11 Alexandria or later (built and tested with Delphi 13 Florence).
- DelphiMVCFramework 3.4.0 or later. The project finds the DMVC sources through the `DMVC_HOME` environment variable, which must point to the DMVC folder (the one that contains `sources` and `lib`).

The demo was tested with DMVC 3.5.0-silicon-rc6, and its code compiles and runs with the 3.4.0 and 3.4.3 sources. Note that DMVC 3.4.x itself does not compile with Delphi 13 (because of `MVCFramework.ActiveRecord`): with Delphi 13 use DMVC 3.5.

## Build and run

From the IDE, open `Murphy.Demos.DMVC.dproj` and run it. The IDE reads `DMVC_HOME` from the Windows environment when it starts, or from *Tools > Options > IDE > Environment Variables*.

From the command line:

```bat
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild Demos\01_DMVC\Murphy.Demos.DMVC.dproj /p:Config=Debug /p:Platform=Win32
Demos\01_DMVC\Win32\Debug\Murphy.Demos.DMVC.exe
```

The server listens on port 8080: open <http://localhost:8080/> for the dashboard. Press ENTER in the console to stop it. The console log shows every injection (`Chaos: ...`) and every reaction of the resilience policies (`Exchange rates: ...`).

## How it works

```text
request ─► TMVCStaticFilesMiddleware   serves the dashboard (www folder) at /
        ─► TChaosMiddleware            OnBeforeRouting: is the request in the blast radius?
                                       OnBeforeControllerAction, /api only:
                                         Chaos Fault ─► Chaos Latency
        ─► TShopController             GET /api/products
                                       GET /api/products/($id)/price/($currency)
                                         └─► TExchangeRatesClient.GetRate
                                               Fallback ─► Retry ─► Circuit Breaker ─► Timeout
                                                 ─► Chaos Fault ─► Chaos Latency ─► service
        ─► TChaosController            GET/PUT /chaos, local machine only
```

| Unit | Role |
|---|---|
| `ChaosSettingsU` | **Chaos kit.** Thread-safe settings for each chaos target, the blast radius of the current request (`TChaosScope`), and a factory for the chaos policies. It does not use DMVC. |
| `ChaosMiddlewareU` | **Chaos kit.** `TChaosMiddleware`: decides the blast radius and injects chaos into the incoming requests. |
| `ChaosControllerU` | **Chaos kit.** `TChaosController`: the `/chaos` endpoints. |
| `ExchangeRatesU` | The client of the exchange rates service, protected by the resilience policies. |
| `ShopControllerU` | The API: a product list and a price converted with the exchange rates. |
| `WebModuleU` | The DMVC engine with its middlewares and controllers. |
| `www/` | The dashboard: plain HTML, CSS and JavaScript, without external dependencies. |

At startup (see `ConfigureChaos` in the `.dpr`) the settings are:

| Target | Fault rate | Latency rate | Latency |
|---|---|---|---|
| `inbound` (incoming requests) | 10% | 20% | 200-800 ms |
| `rates` (exchange rates service) | 20% | 20% | 1500-2500 ms |

The exchange rates client uses a 1 second timeout, 2 retries 200 ms apart, and a circuit breaker that opens after 3 consecutive failures and stays open for 5 seconds. The fallback serves the last rate received for the currency.

## Using the chaos kit in your application

The three kit units depend only on Murphy and DMVC. Copy them into your project, then follow these steps.

1. Register the chaos targets at startup, with their initial settings:

   ```pascal
   ChaosSettings.SetTarget(TChaosMiddleware.TargetName,
     TChaosTargetSettings.Create(0.1, 0.2, 200, 800));
   ChaosSettings.SetTarget('database',
     TChaosTargetSettings.Create(0.05, 0.1, 500, 2000));
   ```

2. Add the middleware and the controller to the engine:

   ```pascal
   FEngine
     .AddMiddleware(TChaosMiddleware.Create('/api'))
     .AddController(TChaosController);
   ```

3. Where the application calls a dependency, create the chaos policies of its target at every call, and put them innermost:

   ```pascal
   TPolicyWrapBuilder.Wrap([
     FRetry,
     FBreaker,
     FTimeout,
     ChaosSettings.CreateFault('database').Fault(EDatabaseError, 'Connection lost'),
     ChaosSettings.CreateLatency('database')
   ]).Execute(
     procedure
     begin
       RunQuery;
     end);
   ```

4. Keep chaos out of production: set `MurphyChaosEnabled := False` (e.g. under `{$IFDEF RELEASE}`), or do not register the middleware and the controller.

## Design notes

- **Chaos policies are created for every request.** They read the current settings and the blast radius of the request, and creating them is cheap. A resilience policy with state, such as the circuit breaker, is created once and shared instead, otherwise it would never see the failures of the other requests. WebBroker creates a web module, and so a DMVC engine, for every request served at the same time. For this reason the shared state lives in global objects (`ChaosSettings`, `ExchangeRates`) and never in a middleware.
- **The blast radius travels in a thread variable.** The middleware decides it in `OnBeforeRouting`, and the code of the request reads it through `TChaosScope`. A thread variable is visible only on the thread that serves the request, while a Timeout policy runs its action on a pool thread. So the chaos policies read the scope when they are created, on the request thread, and not in a generator at execution time. Keep in mind that a generator (`EnabledGenerator`, `InjectionRateGenerator`, ...) runs on the thread that executes the policy.
- **A middleware hook has no "next" to wrap.** DMVC calls the action after `OnBeforeControllerAction`, so the middleware runs the policies on an empty action. The latency delays the request. The fault is an `EMVCException` with status 503, which DMVC turns into the error response.
- **A timeout abandons an attempt, it does not cancel it.** An attempt cut off by the timeout keeps running on its pool thread until the injected latency ends. Each attempt therefore stores its result in a variable of its own, so a late attempt cannot overwrite the next one. The simulated service is a plain routine, not a method, because a late attempt can outlive the client while the application shuts down.
- **Shared state widens the blast radius.** The circuit breaker is shared by all the requests. When the test traffic opens it, the normal traffic gets cached rates too, even though no chaos is injected into its requests. Finding couplings like this one is the point of a chaos experiment: see test 9 of the [testing guide](TESTING.md).
- The Outcome and Behavior strategies are not used here: the [Primer](../00_Primer) demo shows them.

## Security

- `/chaos` answers only to connections from the local machine. The check uses the address of the socket (`RawWebRequest.RemoteAddr`), not `Request.ClientIp`: up to DMVC 3.4, `ClientIp` trusts the `X-Forwarded-For` header, which any client can forge. With a DMVC 3.5 host other than WebBroker, use `Request.PeerIp`.
- The marker header lets a client inject chaos only into its own requests. Extending chaos to every request requires the control endpoint.
- In production, turn chaos off as described above, or protect the middleware and the controller with authentication.

## API reference

| Request | Description |
|---|---|
| `GET /api/products` | The product list. Only the chaos of the `inbound` target reaches it. |
| `GET /api/products/{id}/price/{currency}` | The price of a product (1-4) in a currency (`USD`, `GBP`, `CHF`, `JPY`), with `rate`, `rateSource` (`live` or `cache`), `attempts` and `circuit` (`Closed`, `Open`, `HalfOpen`). Both chaos targets reach it. |
| `GET /chaos` | The chaos settings. |
| `PUT /chaos` | Changes the settings found in the JSON body and returns them all. |

The chaos settings use this JSON shape. `PUT` accepts any subset of it, validates everything, and changes nothing if a value is invalid (status 400). `markerHeader` is read-only.

```json
{
  "enabled": true,
  "blastRadius": "marked",
  "markerHeader": "X-Chaos",
  "targets": {
    "inbound": { "faultRate": 0.1, "latencyRate": 0.2, "latencyMinMs": 200, "latencyMaxMs": 800 },
    "rates": { "faultRate": 0.2, "latencyRate": 0.2, "latencyMinMs": 1500, "latencyMaxMs": 2500 }
  }
}
```

| Header | Description |
|---|---|
| `X-Chaos: on` | Request header that puts the request in the blast radius. |
| `X-Chaos-Injected` | Response header that tells which chaos the incoming request received: `fault` or `latency=<ms>`. |
