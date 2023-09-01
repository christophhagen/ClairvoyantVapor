# ClairvoyantVapor

Useful extensions for exposing [Clairvoyant](https://github.com/christophhagen/Clairvoyant) metrics through a [Vapor](https://vapor.codes) server.

The package provides a `MetricsProvider` to serve as a `MetricFactory`, so you can do:

```swift
let metrics = MetricsProvider(...)
MetricsSystem.bootstrap(metrics)
```

For more information, see the [documentation](https://github.com/christophhagen/Clairvoyant#usage-with-swift-metrics) of the [Clairvoyant framework](https://github.com/christophhagen/Clairvoyant).


