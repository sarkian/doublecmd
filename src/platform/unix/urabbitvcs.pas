unit uRabbitVCS;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Menus, Graphics, uPixMapManager;

const
  RabbitVCSAddress   = 'org.google.code.rabbitvcs.RabbitVCS.Checker';
  RabbitVCSObject    = '/org/google/code/rabbitvcs/StatusChecker';
  RabbitVCSInterface = 'org.google.code.rabbitvcs.StatusChecker';

type
  TVcsStatus = (vscNormal, vscModified, vscAdded, vscDeleted, vscIgnored,
                vscReadOnly, vscLocked, vscUnknown, vscMissing, vscReplaced,
                vscComplicated, vscCalculating, vscError, vscUnversioned);

const
  VcsStatusText: array[TVcsStatus] of UTF8String =
                                         (
                                         'normal',
                                         'modified',
                                         'added',
                                         'deleted',
                                         'ignored',
                                         'locked',
                                         'locked',
                                         'unknown',
                                         'missing',
                                         'replaced',
                                         'complicated',
                                         'calculating',
                                         'error',
                                         'unversioned'
                                         );

  VcsStatusEmblems: array[TVcsStatus] of UTF8String =
                                         (
                                         'emblem-rabbitvcs-normal',
                                         'emblem-rabbitvcs-modified',
                                         'emblem-rabbitvcs-added',
                                         'emblem-rabbitvcs-deleted',
                                         'emblem-rabbitvcs-ignored',
                                         'emblem-rabbitvcs-locked',
                                         'emblem-rabbitvcs-locked',
                                         'emblem-rabbitvcs-unknown',
                                         'emblem-rabbitvcs-complicated',
                                         'emblem-rabbitvcs-modified',
                                         'emblem-rabbitvcs-complicated',
                                         'emblem-rabbitvcs-calculating',
                                         'emblem-rabbitvcs-error',
                                         'emblem-rabbitvcs-unversioned'
                                         );

{en
   Requests a status check from the underlying status checker.
}
function CheckStatus(Path: UTF8String; Recurse: Boolean32 = False;
                     Invalidate: Boolean32 = True; Summary: Boolean32 = False): string;

function GenerateMenuConditions(Paths: TStringList): string;

var
  RabbitVCS: Boolean = False;

implementation

uses
  dbus, unixtype, fpjson, jsonparser, unix;

var
  error: DBusError;
  conn: PDBusConnection;

procedure Print(const sMessage: String);
begin
  WriteLn('RabbitVCS: ', sMessage);
end;

function CheckError(const sMessage: String; pError: PDBusError): Boolean;
begin
  if (dbus_error_is_set(pError) <> 0) then
  begin
    Print(sMessage + ': ' + pError^.name + ' ' + pError^.message);
    dbus_error_free(pError);
    Result := True;
  end
  else
    Result := False;
end;

function CheckService: Boolean;
const
  RunStatusChecker = 'echo "from rabbitvcs.services.checkerservice import StatusCheckerStub' +
                     #13 + 'status_checker = StatusCheckerStub()' + #13 + '" | python';
var
  service_exists: dbus_bool_t;
begin
  dbus_error_init(@error);
  // Check if RabbitVCS service is running
  service_exists := dbus_bus_name_has_owner(conn, RabbitVCSAddress, @error);
  if CheckError('Cannot query RabbitVCS on DBUS', @error) then
    Exit(False);

  Result:= service_exists <> 0;
  if Result then
    Print('Service found running.')
  else
    begin
      Result:= fpSystem(RunStatusChecker) = 0;
      if Result then
        Print('Service successfully started.');
    end;
end;

function CheckStatus(Path: UTF8String; Recurse: Boolean32;
                     Invalidate: Boolean32; Summary: Boolean32): string;
var
  Return: Boolean;
  StringPtr: PAnsiChar;
  JAnswer : TJSONObject;
  VcsStatus: TVcsStatus;
  message: PDBusMessage;
  argsIter: DBusMessageIter;
  pending: PDBusPendingCall;
begin
  if not RabbitVCS then Exit;

  // Create a new method call and check for errors
  message := dbus_message_new_method_call(RabbitVCSAddress,   // target for the method call
                                          RabbitVCSObject,    // object to call on
                                          RabbitVCSInterface, // interface to call on
                                          'CheckStatus');     // method name
  if (message = nil) then
  begin
    Print('Cannot create message "CheckStatus"');
    Exit;
  end;

  try
    // Append arguments
    StringPtr:= PAnsiChar(Path);
    dbus_message_iter_init_append(message, @argsIter);
    Return:= (dbus_message_iter_append_basic(@argsIter, DBUS_TYPE_STRING, @StringPtr) <> 0);
    Return:= Return and (dbus_message_iter_append_basic(@argsIter, DBUS_TYPE_BOOLEAN, @Recurse) <> 0);
    Return:= Return and (dbus_message_iter_append_basic(@argsIter, DBUS_TYPE_BOOLEAN, @Invalidate) <> 0);
    Return:= Return and (dbus_message_iter_append_basic(@argsIter, DBUS_TYPE_BOOLEAN, @Summary) <> 0);

    if not Return then
    begin
      Print('Cannot append arguments');
      Exit;
    end;

    // Send message and get a handle for a reply
    if (dbus_connection_send_with_reply(conn, message, @pending, -1) = 0) then
    begin
      Print('Error sending message');
      Exit;
    end;

    if (pending = nil) then
    begin
      Print('Pending call is null');
      Exit;
    end;

    dbus_connection_flush(conn);

  finally
    dbus_message_unref(message);
  end;

  // Block until we recieve a reply
  dbus_pending_call_block(pending);
  // Get the reply message
  message := dbus_pending_call_steal_reply(pending);
  // Free the pending message handle
  dbus_pending_call_unref(pending);

  if (message = nil) then
  begin
    Print('Reply is null');
    Exit;
  end;

  try
    // Read the parameters
    if (dbus_message_iter_init(message, @argsIter) <> 0) then
    begin
      if (dbus_message_iter_get_arg_type(@argsIter) = DBUS_TYPE_STRING) then
      begin
        dbus_message_iter_get_basic(@argsIter, @StringPtr);

        with TJSONParser.Create(StrPas(StringPtr)) do
        try
          JAnswer:= Parse as TJSONObject;
          try
            Result:= JAnswer.Strings['content'];
            if Result = 'unknown' then Exit(EmptyStr);
          except
            Exit(EmptyStr);
          end;
          JAnswer.Free;
        finally
          Free;
        end;

        for VcsStatus:= Low(TVcsStatus) to High(VcsStatus) do
        begin
          if (VcsStatusText[VcsStatus] = Result) then
          begin
            Result:= VcsStatusEmblems[VcsStatus];
            Break;
          end;
        end;
      end;
    end;
  finally
    dbus_message_unref(message);
  end;
end;

function GenerateMenuConditions(Paths: TStringList): string;
var
  I: Integer;
  Return: Boolean;
  StringPtr: PAnsiChar;
  optsPChar: PAnsiChar;
  message: PDBusMessage;
  pending: PDBusPendingCall;
  argsIter, arrayIter: DBusMessageIter;
begin
  if not RabbitVCS then Exit;

  // Create a new method call and check for errors
  message := dbus_message_new_method_call(RabbitVCSAddress,          // target for the method call
                                          RabbitVCSObject,           // object to call on
                                          RabbitVCSInterface,        // interface to call on
                                          'GenerateMenuConditions'); // method name
  if (message = nil) then
  begin
    Print('Cannot create message "GenerateMenuConditions"');
    Exit;
  end;

  try
    dbus_message_iter_init_append(message, @argsIter);
    Return := dbus_message_iter_open_container(@argsIter, DBUS_TYPE_ARRAY, PChar(DBUS_TYPE_STRING_AS_STRING), @arrayIter) <> 0;
    if Return then
    begin
      for I := 0 to Paths.Count - 1 do
      begin
        optsPChar := PAnsiChar(Paths[I]);
        if dbus_message_iter_append_basic(@arrayIter, DBUS_TYPE_STRING, @optsPChar) = 0 then
        begin
          Print('Cannot append arguments');
          Exit;
        end;
      end;

      if dbus_message_iter_close_container(@argsIter, @arrayIter) = 0 then
      begin
        Print('Cannot append arguments');
        Exit;
      end;
    end;

    // Send message and get a handle for a reply
    if (dbus_connection_send_with_reply(conn, message, @pending, -1) = 0) then // -1 is default timeout
    begin
      Print('Error sending message');
      Exit;
    end;

    if (pending = nil) then
    begin
      Print('Pending call is null');
      Exit;
    end;

    dbus_connection_flush(conn);

  finally
    dbus_message_unref(message);
  end;

  // Block until we recieve a reply
  dbus_pending_call_block(pending);
  // Get the reply message
  message := dbus_pending_call_steal_reply(pending);
  // Free the pending message handle
  dbus_pending_call_unref(pending);

  if (message = nil) then
  begin
    Print('Reply is null');
    Exit;
  end;

  try
    // Read the parameters
    if (dbus_message_iter_init(message, @argsIter) <> 0) then
    begin
      if (dbus_message_iter_get_arg_type(@argsIter) = DBUS_TYPE_STRING) then
      begin
        dbus_message_iter_get_basic(@argsIter, @StringPtr);

        Result:= StrPas(StringPtr);
      end;
    end;
  finally
    dbus_message_unref(message);
  end;
end;

procedure Initialize;
begin
  dbus_error_init(@error);
  conn := dbus_bus_get(DBUS_BUS_SESSION, @error);
  if CheckError('Cannot acquire connection to DBUS session bus', @error) then
    Exit;
  RabbitVCS:= CheckService;
end;

procedure Finalize;
begin
  dbus_connection_close(conn);
end;

initialization
  Initialize;

finalization
  Finalize;

end.

