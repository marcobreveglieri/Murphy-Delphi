program Murphy.Tests;

{$IFNDEF TESTINSIGHT}
  {$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ELSE}
  DUnitX.Loggers.Console,
  {$ENDIF }
  DUnitX.TestFramework,
  Murphy.Tests.Bulkhead in 'Murphy.Tests.Bulkhead.pas',
  Murphy.Tests.Cache in 'Murphy.Tests.Cache.pas',
  Murphy.Tests.CircuitBreaker in 'Murphy.Tests.CircuitBreaker.pas',
  Murphy.Tests.Fallback in 'Murphy.Tests.Fallback.pas',
  Murphy.Tests.Hedging in 'Murphy.Tests.Hedging.pas',
  Murphy.Tests.PolicyWrap in 'Murphy.Tests.PolicyWrap.pas',
  Murphy.Tests.RateLimit in 'Murphy.Tests.RateLimit.pas',
  Murphy.Tests.Retry in 'Murphy.Tests.Retry.pas',
  Murphy.Tests.Timeout in 'Murphy.Tests.Timeout.pas';

begin
  ReportMemoryLeaksOnShutdown := True;
{$IFDEF TESTINSIGHT}
  TestInsight.DUnitX.RunRegisteredTests;
{$ELSE}
  try
    //Check command line options, will exit if invalid
    TDUnitX.CheckCommandLine;

    //Create the test LRunner
    var LRunner := TDUnitX.CreateRunner;

    //Tell the LRunner to use RTTI to find Fixtures
    LRunner.UseRTTI := True;

    //When true, Assertions must be made during tests;
    LRunner.FailsOnNoAsserts := False;

    //tell the LRunner how we will log things
    //Log to the console window if desired
    if TDUnitX.Options.ConsoleMode <> TDunitXConsoleMode.Off then
      LRunner.AddLogger(TDUnitXConsoleLogger.Create(TDUnitX.Options.ConsoleMode = TDunitXConsoleMode.Quiet));

    //Run tests
    var LResults := LRunner.Execute;
    if not LResults.AllPassed then
      System.ExitCode := EXIT_ERRORS;

    {$IFNDEF CI}
    //We don't want this happening when running under CI.
    System.Write('Done.. press <Enter> key to quit.');
    System.Readln;
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
{$ENDIF}
end.
