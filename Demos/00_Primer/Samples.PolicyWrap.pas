unit Samples.PolicyWrap;

interface

procedure RunPolicyWrapSample;

implementation

uses
  System.SysUtils,
  System.TimeSpan,
  Murphy.Policy.Retry,
  Murphy.Policy.Timeout,
  Murphy.Policy.Wrap;

procedure RunPolicyWrapSample;
begin
  // Combines Retry (outer) and Timeout (inner): each attempt has
  // its own timeout, and attempts that time out are retried.
  var LWrap := TPolicyWrapBuilder.Wrap([
    TRetryBuilder
      .Handle(ETimeoutRejectedException)
      .Retry(3)
      .Wait(TTimeSpan.FromMilliseconds(500)),
    TTimeoutBuilder
      .Handle([])
      .After(TTimeSpan.FromSeconds(1))
  ]);

  var LAttempts := 0;

  try
    LWrap.Execute(
      procedure
      begin
        Inc(LAttempts);
        Writeln('Calling the database... (attempt no. ', LAttempts, ')');
        // The first two attempts exceed the 1-second timeout.
        if LAttempts <= 2 then
          Sleep(2000);
        Writeln('Call completed successfully!');
      end
    );
  except on E: Exception do
    Writeln(E.ClassName, ': ', E.Message);
  end;
end;

end.
