unit Murphy.Globals;

interface

var
  /// <summary>
  ///  This flag can be set to enable test mode.
  /// </summary>
  /// <remarks>
  ///  When test mode is enabled, all the services
  ///  are replaced by virtual (or mocked) instances.
  /// </remarks>
  MurphyTestModeEnabled: Boolean;

  /// <summary>
  ///  This flag can be cleared to disable every chaos policy.
  /// </summary>
  /// <remarks>
  ///  When chaos is disabled, chaos policies never inject anything
  ///  regardless of their own settings: this is the master switch to
  ///  turn off chaos centrally, e.g. in production builds.
  /// </remarks>
  MurphyChaosEnabled: Boolean;

implementation

initialization

  MurphyTestModeEnabled := False;
  MurphyChaosEnabled := True;

end.
