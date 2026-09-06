using System.Diagnostics;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

// 1. Native .NET BCL Tracing Primitives
public static class Telemetry
{
    public const string ServiceName = "PaymentService";
    public const string ServiceVersion = "1.5.0";
    public static readonly ActivitySource ActivitySource = new(ServiceName, ServiceVersion);
}

var builder = WebApplication.CreateBuilder(args);

// 2. Configure OpenTelemetry SDK with OTLP Exporter
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: Telemetry.ServiceName, serviceVersion: Telemetry.ServiceVersion)
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment"] = "production",
            ["host.region"] = "us-east-1"
        }))
    .WithTracing(tracing => tracing
        .AddSource(Telemetry.ServiceName)
        .AddAspNetCoreInstrumentation(options =>
        {
            options.RecordException = true;
            options.Filter = httpContext => !httpContext.Request.Path.StartsWithSegments("/healthz");
        })
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://otel-gateway.monitoring.svc:4317");
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri("http://otel-gateway.monitoring.svc:4317");
        }));

// 3. Structured Logging Correlation
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    logging.ParseStateValues = true;
});

var app = builder.Build();

app.MapGet("/charge/{amount:decimal}", async (decimal amount, ILogger<Program> logger) =>
{
    // Native ActivitySource span creation
    using Activity? activity = Telemetry.ActivitySource.StartActivity("ProcessCharge", ActivityKind.Internal);
    
    activity?.SetTag("payment.amount", amount);
    activity?.SetTag("payment.currency", "USD");

    logger.LogInformation("Processing payment charge of {Amount:C}", amount);

    await Task.Delay(50); // Simulate transaction

    if (amount <= 0)
    {
        activity?.SetStatus(ActivityStatusCode.Error, "Invalid charge amount");
        return Results.BadRequest(new { error = "Amount must be positive" });
    }

    activity?.SetStatus(ActivityStatusCode.Ok);
    return Results.Ok(new { status = "approved", amount });
});

app.MapGet("/healthz", () => Results.Ok("healthy"));

app.Run();
