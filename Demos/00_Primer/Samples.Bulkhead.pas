unit Samples.Bulkhead;

interface

procedure RunBulkheadSample;

implementation

uses
  System.SysUtils,
  System.Threading,
  Murphy.Policy.Bulkhead;

procedure RunBulkheadSample;
begin
  var LPolicy := TBulkheadBuilder
    .Handle(ENotImplemented)
    .Limit(3);

  var LTasks: TArray<ITask>;
  SetLength(LTasks, 10);

  for var LTaskIndex := 0 to High(LTasks) do
  begin
    var LTaskNumber := LTaskIndex + 1;
    LTasks[LTaskIndex] := TTask.Run(
      procedure
      begin
        try
          LPolicy.Execute(
            procedure
            begin
              Writeln('Task no. ', LTaskNumber, ': slot acquired, work in progress...');
              Sleep(500);
            end
          );
        except on E: Exception do
          Writeln('Task no. ', LTaskNumber, ' rejected - ', E.ClassName, ': ', E.Message);
        end;
      end);
    Sleep(20);
  end;

  TTask.WaitForAll(LTasks);
  Writeln('All tasks have finished.');
end;

end.
