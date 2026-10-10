unit Samples.Chaos;

interface

procedure RunChaosSample;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Chaos.Fault,
  Murphy.Chaos.Latency,
  Murphy.Policy.Retry,
  Murphy.Policy.Wrap;

procedure RunChaosSample;
begin
  // A healthy service made unreliable on purpose: the chaos policies
  // go last (innermost) in the wrap, so about half of the attempts get
  // a fault and about a third get a delay, and the retry around them
  // must cope with both.
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(EChaosFaultException)
      .Retry(5)
      .Wait(TTimeSpan.FromMilliseconds(500)),
    TChaosFaultBuilder
      .InjectionRate(0.5)
      .OnFaultInjected(
        procedure(AContext: TChaosFaultContext)
        begin
          Writeln('  Chaos: fault injected (', AContext.Fault.ClassName, ')');
        end),
    TChaosLatencyBuilder
      .InjectionRate(0.3)
      .Latency(TTimeSpan.FromSeconds(1))
      .OnLatencyInjected(
        procedure(AContext: TChaosLatencyContext)
        begin
          Writeln('  Chaos: latency injected (', AContext.Latency.TotalMilliseconds:0:0, ' ms)');
        end)
  ]);

  for var LCall := 1 to 5 do
  begin
    Writeln('Calling the service... (call no. ', LCall, ')');
    try
      LWrap.Execute(
        procedure
        begin
          Writeln('  Service reached!');
        end
      );
      Writeln('Call completed successfully!');
    except on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
    end;
    Writeln;
  end;
end;

end.
