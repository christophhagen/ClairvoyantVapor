# ClairvoyantVapor

Useful extensions for exposing [Clairvoyant](https://github.com/christophhagen/Clairvoyant) metrics through a [Vapor](https://vapor.codes) server.

## Prerequisites

To use `ClairvoyantVapor`, first familiarize yourself with the [Clairvoyant framework](https://github.com/christophhagen/Clairvoyant).
Once a Vapor server application has metrics set up, you can expose the metrics through `Vapor` itself.

## Usage

Each `MetricObserver` can be exposed separately on a subpath of the server.

```swift
import Clairvoyant
import ClairvoyantVapor

func configure(app: Application) {
    let observer = MetricObserver(...)
    let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
    observer.registerRoutes(app)
}
```

This will add a number of routes to the default path, which is `/metrics`.
The path can also be passed as a parameter to `registerRoutes()`.

```swift
observer.registerRoutes(app, subPath: "/metrics")
```

### Access control

A `VaporMetricProvider` requires an access manager, as seen in the example above.
Since the metrics may contain sensitive data, they should only be accessible by authorized entities.
Access control is left to the application, since there may be many ways to handle authentication and access control.
To manage access control, a `RequestAccessManager` must be provided for each metric provider.

```swift
final class MyAuthenticator: RequestAccessManager {

    func getAllowedMetrics(for request: Request, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        throw MetricError.accessDenied
    }
}
```

The authenticator must be provided to the initializer of a `VaporMetricProvider`.

```swift
let provider = VaporMetricProvider(observer: observer, accessManager: MyAuthenticator())
```

If the authentication should be based on access tokens, it's also possible to implement `TokenAccessManager`.
When using this type (or when directly using tokens, see below), then the string value of the token(s) is compared to the content of the HTTP header field `token`.

```swift
final class MyAuthenticator: TokenAccessManager {
    
    func getAllowedMetrics(for accessToken: String, on route: ServerRoute, accessing metrics: [MetricIdHash]) throws -> [MetricIdHash] {
        throw MetricError.accessDenied
    }
}
```

There are also a number of other ways to directly use access tokens.

#### A single `String`

```swift
let provider = VaporMetricProvider(observer: observer, accessManager: "MySecret")
```

#### Multiple `String`s

```swift
let provider = VaporMetricProvider(observer: observer, accessManager: ["MySecret", "MyOtherSecret"])
```        

#### One or more scoped access tokens

```swift
let token1 = ScopedAccessToken(token: "MySecret", permissions: [.list])
let token2 = ScopedAccessToken(token: "MyOtherSecret", permissions: [.list])
let provider = VaporMetricProvider(observer: observer, accessManager: token1)
let provider2 = VaporMetricProvider(observer: observer, accessManager: [token1, token2])
```

Scoped access tokens offer some flexibility to allow fine-grained access to specific metrics or functions.

A scoped access token can have explicit permissions for different functions (`list`, `lastValue`, `push`, `history`).
If the `accessibleMetrics` parameter is empty, then all metrics will be accessible, except for the ones explicitly denied by `inaccessibleMetrics`.
If one or more accessible metrics is defined, then only those can be accessed by the token.

### API

Now that the metrics are protected, they can be accessed by authorized entities. 
The available routes are detailed below.
All requests are `POST` requests, and require authentication. 
**Note**: If the included clients are used, then the API is already correctly implemented and not important. 

#### List all metrics

Get a list of all metrics available on the server.

|   |   |
| --- | --- |
| Route   | `/<subPath>/list` |
| Type  | `POST` |
| Body | `nil` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `[MetricInfo]`, encoded with the encoder assigned to `MetricObserver`. The metric list is filtered according to the access providers response during authentication. |

When using `ScopedAccessToken`, then the scope of `list` is needed for the token. The resulting list will not contain any metrics explicitly denied by the `inaccessibleMetrics` parameter.

#### List of all metrics including last values

Get a list of all metrics available on the server.

|   |   |
| --- | --- |
| Route   | `/<subPath>/list/extended` |
| Type  | `POST` |
| Body | `nil` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `[ExtendedMetricInfo]`, encoded with the encoder assigned to `MetricObserver`. The list is filtered according to the access providers response during authentication. |

When using `ScopedAccessToken`, then the scope of both `list` and `lastValue` is needed for the token. The resulting list will not contain any metrics explicitly denied by the `inaccessibleMetrics` parameter.

#### Last value of metric

Get the last recorded value of a specific metric.

|   |   |
| --- | --- |
| Route   | `/<subPath>/last/<METRIC_ID_HASH>` |
| Type  | `POST` |
| Body | `nil` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `Timestamped<T>`, encoded with the encoder assigned to `MetricObserver`. |

The `<METRIC_ID_HASH>` are the first 16 bytes of the SHA256 hash of the metric `ID` as a hex string (32 characters).
If no value exists yet, then status `410` is returned.

#### Get info of a metric

Get the detailed metric information from a metric id.

|   |   |
| --- | --- |
| Route   | `/<subPath>/info/<METRIC_ID_HASH>` |
| Type  | `POST` |
| Body | `nil` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `MetricInfo`, encoded with the encoder assigned to `MetricObserver`. |

#### Get historic values

Get the logged values of a metric in a specified time interval. 

|   |   |
| --- | --- |
| Route   | `/<subPath>/history/<METRIC_ID_HASH>` |
| Type  | `POST` |
| Body | `MetricHistoryRequest` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `[Timestamped<T>]`, encoded with the encoder assigned to `MetricObserver`. |

The `<METRIC_ID_HASH>` are the first 16 bytes of the SHA256 hash of the metric `ID` as a hex string (32 characters).
If no value exists yet, then status `410` is returned.

The `MetricHistoryRequest` in the body contains the start and end dates of the interval, and a maximum count of elements to return.
The request can be performed chronologically (start < end) or reversed (end > start).
The response is a `[Timestamped<T>]` with the values in the provided range (up to the given limit).

#### Update metric values

Update the value of a metric remotely.

Add values to a metric through the web interface. 
This function is mostly needed to push metrics to other vapor servers.

|   |   |
| --- | --- |
| Route   | `/<subPath>/push/<METRIC_ID_HASH>` |
| Type  | `POST` |
| Body | `[Timestamped<T>]` |
| Headers | `token` with the authentication token, if using simple `String` tokens or `ScopedAccessToken` |
| Response | `[Timestamped<T>]`, encoded with the encoder assigned to `MetricObserver`. |

Updating a metric is only allowed if `canBeUpdatedByRemote` is set to `true` when the metric is created.

For more information, see the documentation of the [Clairvoyant framework](https://github.com/christophhagen/Clairvoyant).


