unit uFileSystemUtil;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, uDescr, uLog, uGlobs, DCOSUtils,
  uFile,
  uFileSourceOperation,
  uFileSourceOperationOptions,
  uFileSourceOperationUI,
  uFileSourceCopyOperation,
  uSearchTemplate,
  uFindFiles;

  function ApplyRenameMask(aFile: TFile; NameMask: String; ExtMask: String): String; overload;
  procedure FillAndCount(Files: TFiles;
                         CountDirs: Boolean;
                         ExcludeRootDir: Boolean;
                         out NewFiles: TFiles;
                         out FilesCount: Int64;
                         out FilesSize: Int64);
  function FileExistsMessage(const TargetName, SourceName: UTF8String;
                             SourceSize: Int64; SourceTime: TDateTime): UTF8String;

type
  // Additional data for the filesystem tree node.
  TFileTreeNodeData = class
  public
    // True if any of the subnodes (recursively) are links.
    SubnodesHaveLinks: Boolean;
    // Whether directory or subdirectories have any elements that will not be copied/moved.
    SubnodesHaveExclusions: Boolean;
  end;

  TUpdateStatisticsFunction = procedure(var NewStatistics: TFileSourceCopyOperationStatistics) of object;

  TFileSystemOperationTargetExistsResult =
    (fsoterNotExists, fsoterDeleted, fsoterAddToTarget, fsoterResume,
     fsoterSkip);

  TFileSystemOperationHelperMode =
    (fsohmCopy, fsohmMove);

  TFileSystemOperationHelperCopyMode =
    (fsohcmDefault, fsohcmAppend, fsohcmResume);

  TFileSystemOperationHelperMoveOrCopy
    = function(SourceFile: TFile; TargetFileName: String;
               Mode: TFileSystemOperationHelperCopyMode): Boolean of object;

  { TFileSystemTreeBuilder }

  TFileSystemTreeBuilder = class
  private
    FFilesTree: TFileTree;
    FFilesCount: Int64;
    FCurrentDepth: Integer;
    FDirectoriesCount: Int64;
    FFilesSize: Int64;
    FExcludeRootDir: Boolean;
    FFileTemplate: TSearchTemplate;
    FExcludeEmptyTemplateDirectories: Boolean;
    FSymlinkOption: TFileSourceOperationOptionSymLink;
    FRecursive: Boolean;
    FFileChecks: TFindFileChecks;
    FRootDir: String;

    AskQuestion: TAskQuestionFunction;
    CheckOperationState: TCheckOperationStateFunction;

    procedure AddItem(aFile: TFile; CurrentNode: TFileTreeNode);
    procedure AddFilesInDirectory(srcPath: String; CurrentNode: TFileTreeNode);
    procedure AddFile(aFile: TFile; CurrentNode: TFileTreeNode);
    procedure AddLink(aFile: TFile; CurrentNode: TFileTreeNode);
    procedure AddLinkTarget(aFile: TFile; CurrentNode: TFileTreeNode);
    procedure AddDirectory(aFile: TFile; CurrentNode: TFileTreeNode);
    procedure DecideOnLink(aFile: TFile; CurrentNode: TFileTreeNode);

    function GetItemsCount: Int64;

  public
    constructor Create(AskQuestionFunction: TAskQuestionFunction;
                       CheckOperationStateFunction: TCheckOperationStateFunction);
    destructor Destroy; override;

    procedure BuildFromFiles(Files: TFiles);
    function ReleaseTree: TFileTree;

    property ExcludeRootDir: Boolean read FExcludeRootDir write FExcludeRootDir;
    property Recursive: Boolean read FRecursive write FRecursive;
    property SymLinkOption: TFileSourceOperationOptionSymLink read FSymlinkOption write FSymlinkOption;

    property FilesTree: TFileTree read FFilesTree;
    property FilesSize: Int64 read FFilesSize;
    property FilesCount: Int64 read FFilesCount;
    property DirectoriesCount: Int64 read FDirectoriesCount;
    property ItemsCount: Int64 read GetItemsCount;
    property ExcludeEmptyTemplateDirectories: Boolean read FExcludeEmptyTemplateDirectories write FExcludeEmptyTemplateDirectories;
    {en
       Does not take ownership of SearchTemplate and does not free it.
    }
    property SearchTemplate: TSearchTemplate read FFileTemplate write FFileTemplate;
  end;

  { TFileSystemOperationHelper }

  TFileSystemOperationHelper = class
  private
    FOperationThread: TThread;
    FMode: TFileSystemOperationHelperMode;
    FBuffer: Pointer;
    FBufferSize: LongWord;
    FRootTargetPath: String;
    FRenameMask: String;
    FRenameNameMask, FRenameExtMask: String;
    FSetPropertyError: TFileSourceOperationOptionSetPropertyError;
    FStatistics: TFileSourceCopyOperationStatistics; // local copy of statistics
    FDescription: TDescription;
    FLogCaption: String;
    FRenamingFiles: Boolean;
    FRenamingRootDir: Boolean;
    FRootDir: TFile;
    FReserveSpace,
    FCheckFreeSpace: Boolean;
    FSkipAllBigFiles: Boolean;
    FSkipOpenForReadingError: Boolean;
    FSkipOpenForWritingError: Boolean;
    FSkipReadError: Boolean;
    FSkipWriteError: Boolean;
    FAutoRenameItSelf: Boolean;
    FCorrectSymLinks: Boolean;
    FCopyAttributesOptions: TCopyAttributesOptions;
    FFileExistsOption: TFileSourceOperationOptionFileExists;
    FDirExistsOption: TFileSourceOperationOptionDirectoryExists;

    AskQuestion: TAskQuestionFunction;
    AbortOperation: TAbortOperationFunction;
    CheckOperationState: TCheckOperationStateFunction;
    UpdateStatistics: TUpdateStatisticsFunction;
    MoveOrCopy: TFileSystemOperationHelperMoveOrCopy;

    procedure ShowError(sMessage: String);
    procedure LogMessage(sMessage: String; logOptions: TLogOptions; logMsgType: TLogMsgType);

    function CopyFile(SourceFile: TFile; TargetFileName: String; Mode: TFileSystemOperationHelperCopyMode): Boolean;
    function MoveFile(SourceFile: TFile; TargetFileName: String; Mode: TFileSystemOperationHelperCopyMode): Boolean;
    procedure CopyProperties(SourceFileName, TargetFileName: String);

    function ProcessNode(aFileTreeNode: TFileTreeNode; CurrentTargetPath: String): Boolean;
    function ProcessDirectory(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;
    function ProcessLink(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;
    function ProcessFile(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;

    function TargetExists(aNode: TFileTreeNode; var AbsoluteTargetFileName: String)
                 : TFileSystemOperationTargetExistsResult;
    function DirExists(aFile: TFile;
                       AbsoluteTargetFileName: String;
                       AllowCopyInto: Boolean;
                       AllowDelete: Boolean): TFileSourceOperationOptionDirectoryExists;
    function FileExists(aFile: TFile;
                        var AbsoluteTargetFileName: String;
                        AllowAppend: Boolean): TFileSourceOperationOptionFileExists;

    procedure CountStatistics(aNode: TFileTreeNode);

  public
    constructor Create(AskQuestionFunction: TAskQuestionFunction;
                       AbortOperationFunction: TAbortOperationFunction;
                       CheckOperationStateFunction: TCheckOperationStateFunction;
                       UpdateStatisticsFunction: TUpdateStatisticsFunction;
                       OperationThread: TThread;
                       Mode: TFileSystemOperationHelperMode;
                       TargetPath: String;
                       StartingStatistics: TFileSourceCopyOperationStatistics);
    destructor Destroy; override;

    procedure Initialize;

    procedure ProcessTree(aFileTree: TFileTree);

    property FileExistsOption: TFileSourceOperationOptionFileExists read FFileExistsOption write FFileExistsOption;
    property DirExistsOption: TFileSourceOperationOptionDirectoryExists read FDirExistsOption write FDirExistsOption;
    property CheckFreeSpace: Boolean read FCheckFreeSpace write FCheckFreeSpace;
    property ReserveSpace: Boolean read FReserveSpace write FReserveSpace;
    property SetPropertyError: TFileSourceOperationOptionSetPropertyError read FSetPropertyError write FSetPropertyError;
    property SkipAllBigFiles: Boolean read FSkipAllBigFiles write FSkipAllBigFiles;
    property AutoRenameItSelf: Boolean read FAutoRenameItSelf write FAutoRenameItSelf;
    property CopyAttributesOptions: TCopyAttributesOptions read FCopyAttributesOptions write FCopyAttributesOptions;
    property CorrectSymLinks: Boolean read FCorrectSymLinks write FCorrectSymLinks;
    property RenameMask: String read FRenameMask write FRenameMask;
  end;

implementation

uses
  uDebug, uOSUtils, DCStrUtils, FileUtil, uFindEx, DCClassesUtf8, uFileProcs, uLng,
  uDCUtils, DCBasicTypes, uFileSource, uFileSystemFileSource, uFileProperty,
  StrUtils, DCDateTimeUtils, uShowMsg, Forms;

function ApplyRenameMask(aFile: TFile; NameMask: String; ExtMask: String): String; overload;
begin
  // Only change name for files.
  if aFile.IsDirectory or aFile.IsLink then
    Result := aFile.Name
  else
    Result := ApplyRenameMask(aFile.Name, NameMask, ExtMask);
end;

procedure FillAndCount(Files: TFiles; CountDirs: Boolean; ExcludeRootDir: Boolean;
  out NewFiles: TFiles; out FilesCount: Int64; out FilesSize: Int64);

  procedure FillAndCountRec(const srcPath: String);
  var
    sr: TSearchRecEx;
    aFile: TFile;
  begin
    if FindFirstEx(srcPath + '*', faAnyFile, sr) = 0 then
    begin
      repeat
        if (sr.Name='.') or (sr.Name='..') then Continue;
        aFile := TFileSystemFileSource.CreateFile(srcPath, @sr);

        NewFiles.Add(aFile);
        if aFile.IsLink then
        begin
        end
        else if aFile.IsDirectory then
        begin
          if CountDirs then
            Inc(FilesCount);
          FillAndCountRec(srcPath + sr.Name + DirectorySeparator); // go down to directory
        end
        else
        begin
          FilesSize:= FilesSize + aFile.Size;
          Inc(FilesCount);
        end;
      until FindNextEx(sr) <> 0;
    end;

    FindCloseEx(sr);
  end;

var
  i: Integer;
  aFile: TFile;
begin
  FilesCount:= 0;
  FilesSize:= 0;

  if ExcludeRootDir then
  begin
    if Files.Count <> 1 then
      raise Exception.Create('Only a single directory can be set with ExcludeRootDir=True');
    NewFiles := TFiles.Create(Files[0].FullPath);
    FillAndCountRec(Files[0].FullPath + DirectorySeparator);
  end
  else
  begin
    NewFiles := TFiles.Create(Files.Path);
    for i := 0 to Files.Count - 1 do
    begin
      aFile := Files[i];

      NewFiles.Add(aFile.Clone);

      if aFile.IsDirectory and (not aFile.IsLinkToDirectory) then
      begin
        if CountDirs then
          Inc(FilesCount);
        FillAndCountRec(aFile.Path + aFile.Name + DirectorySeparator);  // recursive browse child dir
      end
      else
      begin
        Inc(FilesCount);
        FilesSize:= FilesSize + aFile.Size; // in first level we know file size -> use it
      end;
    end;
  end;
end;

function FileExistsMessage(const TargetName, SourceName: UTF8String;
                           SourceSize: Int64; SourceTime: TDateTime): UTF8String;
var
  TargetInfo: TSearchRec;
begin
  Result:= rsMsgFileExistsOverwrite + LineEnding + TargetName + LineEnding;
  if mbFileGetAttr(TargetName, TargetInfo) then
  begin
    Result:= Result + Format(rsMsgFileExistsFileInfo, [Numb2USA(IntToStr(TargetInfo.Size)),
                             DateTimeToStr(FileDateToDateTime(TargetInfo.Time))]) + LineEnding;
  end;
  Result:= Result + LineEnding + rsMsgFileExistsWithFile + LineEnding + SourceName + LineEnding +
           Format(rsMsgFileExistsFileInfo, [Numb2USA(IntToStr(SourceSize)), DateTimeToStr(SourceTime)]);
end;

// ----------------------------------------------------------------------------

constructor TFileSystemTreeBuilder.Create(AskQuestionFunction: TAskQuestionFunction;
                                          CheckOperationStateFunction: TCheckOperationStateFunction);
begin
  AskQuestion := AskQuestionFunction;
  CheckOperationState := CheckOperationStateFunction;

  FRecursive := True;
  FSymlinkOption := fsooslNone;
end;

destructor TFileSystemTreeBuilder.Destroy;
begin
  inherited Destroy;
  FFilesTree.Free;
end;

procedure TFileSystemTreeBuilder.BuildFromFiles(Files: TFiles);
var
  i: Integer;
begin
  FreeAndNil(FFilesTree);

  FFilesTree := TFileTreeNode.Create;
  FFilesTree.Data := TFileTreeNodeData.Create;
  FFilesSize := 0;
  FFilesCount := 0;
  FDirectoriesCount := 0;
  FCurrentDepth := 0;
  FRootDir := Files.Path;

  if Assigned(FFileTemplate) then
    SearchTemplateToFindFileChecks(FFileTemplate.SearchRecord, FFileChecks);

  if ExcludeRootDir then
  begin
    for i := 0 to Files.Count - 1 do
      if Files[i].IsDirectory then
        AddFilesInDirectory(Files[i].FullPath + DirectorySeparator, FFilesTree);
  end
  else
  begin
    for i := 0 to Files.Count - 1 do
      AddItem(Files[i].Clone, FFilesTree);
  end;
end;

procedure TFileSystemTreeBuilder.AddFile(aFile: TFile; CurrentNode: TFileTreeNode);
var
  AddedNode: TFileTreeNode;
  AddedIndex: Integer;
begin
  AddedIndex := CurrentNode.AddSubNode(aFile);
  AddedNode := CurrentNode.SubNodes[AddedIndex];
  AddedNode.Data := TFileTreeNodeData.Create;

  Inc(FFilesCount);
  FFilesSize:= FFilesSize + aFile.Size;
  CheckOperationState;
end;

procedure TFileSystemTreeBuilder.AddLink(aFile: TFile; CurrentNode: TFileTreeNode);
var
  AddedNode: TFileTreeNode;
  AddedIndex: Integer;
begin
  AddedIndex := CurrentNode.AddSubNode(aFile);
  AddedNode := CurrentNode.SubNodes[AddedIndex];
  AddedNode.Data := TFileTreeNodeData.Create;

  (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveLinks := True;

  Inc(FFilesCount);
end;

procedure TFileSystemTreeBuilder.AddLinkTarget(aFile: TFile; CurrentNode: TFileTreeNode);
var
  LinkedFilePath: String;
  LinkedFile: TFile = nil;
  AddedNode: TFileTreeNode;
  AddedIndex: Integer;
begin
  LinkedFilePath := mbReadAllLinks(aFile.FullPath);
  if LinkedFilePath <> '' then
  begin
    try
      LinkedFile := TFileSystemFileSource.CreateFileFromFile(LinkedFilePath);

      // Add link to current node.
      AddedIndex := CurrentNode.AddSubNode(aFile);
      AddedNode := CurrentNode.SubNodes[AddedIndex];
      AddedNode.Data := TFileTreeNodeData.Create;
      (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveLinks := True;

      // Then add linked file/directory as a subnode of the link.
      AddItem(LinkedFile, AddedNode);

    except
      on EFileNotFound do
        begin
          // Link target doesn't exist - add symlink instead of target (or ask user).
          AddLink(aFile, CurrentNode);
        end;
    end;
  end
  else
  begin
    // error - cannot follow symlink - adding symlink instead of target (or ask user)
    AddLink(aFile, CurrentNode);
  end;
end;

procedure TFileSystemTreeBuilder.AddDirectory(aFile: TFile; CurrentNode: TFileTreeNode);
var
  AddedNode: TFileTreeNode;
  AddedIndex: Integer;
  NodeData: TFileTreeNodeData;
begin
  AddedIndex := CurrentNode.AddSubNode(aFile);
  AddedNode := CurrentNode.SubNodes[AddedIndex];
  NodeData := TFileTreeNodeData.Create;
  AddedNode.Data := NodeData;

  Inc(FDirectoriesCount);

  if FRecursive then
  begin
    if not Assigned(FFileTemplate) or
       (FFileTemplate.SearchRecord.SearchDepth < 0) or
       (FCurrentDepth <= FFileTemplate.SearchRecord.SearchDepth) then
    begin
      Inc(FCurrentDepth);
      AddFilesInDirectory(aFile.FullPath + DirectorySeparator, AddedNode);
      Dec(FCurrentDepth);
    end;

    if Assigned(FFileTemplate) and FExcludeEmptyTemplateDirectories and
       (AddedNode.SubNodesCount = 0) then
    begin
      CurrentNode.RemoveSubNode(AddedIndex);
      (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveExclusions := True;
    end
    else
    begin
      // Propagate flags to parent.
      if NodeData.SubnodesHaveLinks then
        (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveLinks := True;
      if NodeData.SubnodesHaveExclusions then
        (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveExclusions := True;
    end;
  end;
end;

procedure TFileSystemTreeBuilder.DecideOnLink(aFile: TFile; CurrentNode: TFileTreeNode);
begin
  case FSymLinkOption of
    fsooslFollow:
      AddLinkTarget(aFile, CurrentNode);
    fsooslDontFollow:
      AddLink(aFile, CurrentNode);
    fsooslNone:
      begin
        case AskQuestion('', Format(rsMsgFollowSymlink, [aFile.Name]),
                       [fsourYes, fsourAll, fsourNo, fsourSkipAll],
                       fsourYes, fsourNo)
        of
          fsourYes:
            AddLinkTarget(aFile, CurrentNode);
          fsourAll:
            begin
              FSymLinkOption := fsooslFollow;
              AddLinkTarget(aFile, CurrentNode);
            end;
          fsourNo:
            AddLink(aFile, CurrentNode);
          fsourSkipAll:
            begin
              FSymLinkOption := fsooslDontFollow;
              AddLink(aFile, CurrentNode);
            end;
          else
            raise Exception.Create('Invalid user response');
        end;
      end;
    else
      raise Exception.Create('Invalid symlink option');
  end;
end;

procedure TFileSystemTreeBuilder.AddItem(aFile: TFile; CurrentNode: TFileTreeNode);
var
  Matches: Boolean;
begin
  if Assigned(FFileTemplate) then
  begin
    Matches := CheckFile(FFileTemplate.SearchRecord, FFileChecks, aFile);
    if Matches and (AFile.IsDirectory or AFile.IsLinkToDirectory) then
      Matches := CheckDirectoryNameRelative(FFileChecks, aFile.FullPath, FRootDir);
    if not Matches then
    begin
      (CurrentNode.Data as TFileTreeNodeData).SubnodesHaveExclusions := True;
      Exit;
    end;
  end;

  if aFile.IsDirectory then
    AddDirectory(aFile, CurrentNode)
  else if aFile.IsLink then
    DecideOnLink(aFile, CurrentNode)
  else
    AddFile(aFile, CurrentNode);
end;

procedure TFileSystemTreeBuilder.AddFilesInDirectory(
              srcPath: String;
              CurrentNode: TFileTreeNode);
var
  sr: TSearchRecEx;
  aFile: TFile;
begin
  if FindFirstEx(srcPath + '*', faAnyFile, sr) = 0 then
  begin
    repeat
      if (sr.Name = '.') or (sr.Name = '..') then Continue;

      aFile := TFileSystemFileSource.CreateFile(srcPath, @sr);
      AddItem(aFile, CurrentNode);
    until FindNextEx(sr) <> 0;
  end;

  FindCloseEx(sr);
end;

function TFileSystemTreeBuilder.ReleaseTree: TFileTree;
begin
  Result := FFilesTree;
  FFilesTree := nil;
end;

function TFileSystemTreeBuilder.GetItemsCount: Int64;
begin
  Result := FilesCount + DirectoriesCount;
end;

// ----------------------------------------------------------------------------

constructor TFileSystemOperationHelper.Create(AskQuestionFunction: TAskQuestionFunction;
                                         AbortOperationFunction: TAbortOperationFunction;
                                         CheckOperationStateFunction: TCheckOperationStateFunction;
                                         UpdateStatisticsFunction: TUpdateStatisticsFunction;
                                         OperationThread: TThread;
                                         Mode: TFileSystemOperationHelperMode;
                                         TargetPath: String;
                                         StartingStatistics: TFileSourceCopyOperationStatistics);
begin
  AskQuestion := AskQuestionFunction;
  AbortOperation := AbortOperationFunction;
  CheckOperationState := CheckOperationStateFunction;
  UpdateStatistics := UpdateStatisticsFunction;

  FOperationThread := OperationThread;
  FMode := Mode;

  FBufferSize := gCopyBlockSize;
  GetMem(FBuffer, FBufferSize);

  FCheckFreeSpace := True;
  FSkipAllBigFiles := False;
  FSkipReadError := False;
  FSkipWriteError := False;
  FCopyAttributesOptions := CopyAttributesOptionCopyAll;
  FFileExistsOption := fsoofeNone;
  FDirExistsOption := fsoodeNone;
  FSetPropertyError := fsoospeNone;
  FRootTargetPath := TargetPath;
  FRenameMask := '';
  FStatistics := StartingStatistics;
  FRenamingFiles := False;
  FRenamingRootDir := False;
  FRootDir := nil;

  if gProcessComments then
    FDescription := TDescription.Create(True)
  else
    FDescription := nil;

  case FMode of
    fsohmCopy:
      begin
        MoveOrCopy := @CopyFile;
        FLogCaption := rsMsgLogCopy;
      end;
    fsohmMove:
      begin
        MoveOrCopy := @MoveFile;
        FLogCaption := rsMsgLogMove;
      end;
    else
      raise Exception.Create('Invalid operation mode');
  end;

  inherited Create;
end;

destructor TFileSystemOperationHelper.Destroy;
begin
  inherited Destroy;

  if Assigned(FBuffer) then
  begin
    FreeMem(FBuffer);
    FBuffer := nil;
  end;

  if Assigned(FDescription) then
  begin
    FDescription.SaveDescription;
    FreeAndNil(FDescription);
  end;
end;

procedure TFileSystemOperationHelper.Initialize;
begin
  SplitFileMask(FRenameMask, FRenameNameMask, FRenameExtMask);

  // Create destination path if it doesn't exist.
  if not mbDirectoryExists(FRootTargetPath) then
    if not mbForceDirectory(FRootTargetPath) then
      Exit; // do error
end;

procedure TFileSystemOperationHelper.ProcessTree(aFileTree: TFileTree);
var
  aFile: TFile;
begin
  FRenamingFiles := (FRenameMask <> '*.*') and (FRenameMask <> '');

  // If there is a single root dir and rename mask doesn't have wildcards
  // treat is as a rename of the root dir.
  if (aFileTree.SubNodesCount = 1) and FRenamingFiles then
  begin
    aFile := aFileTree.SubNodes[0].TheFile;
    if (aFile.IsDirectory or aFile.IsLinkToDirectory) and
       not ContainsWildcards(FRenameMask) then
    begin
      FRenamingFiles := False;
      FRenamingRootDir := True;
      FRootDir := aFile;
    end;
  end;

  ProcessNode(aFileTree, FRootTargetPath);
end;

// ----------------------------------------------------------------------------

function TFileSystemOperationHelper.CopyFile(
           SourceFile: TFile;
           TargetFileName: String;
           Mode: TFileSystemOperationHelperCopyMode): Boolean;
var
  SourceFileStream, TargetFileStream: TFileStreamEx;
  iTotalDiskSize, iFreeDiskSize: Int64;
  bRetryRead, bRetryWrite: Boolean;
  BytesRead, BytesToRead, BytesWrittenTry, BytesWritten: Int64;
  TotalBytesToRead: Int64 = 0;
  NewPos: Int64;
  DeleteFile: Boolean = False;

  procedure OpenSourceFile;
  var
    bRetry: Boolean = True;
  begin
    while bRetry do
    begin
      bRetry := False;
      SourceFileStream.Free; // In case stream was created but 'while' loop run again
      try
        SourceFileStream := TFileStreamEx.Create(SourceFile.FullPath, fmOpenRead or fmShareDenyNone);
      except
        on EFOpenError do
          begin
            if not FSkipOpenForReadingError then
            begin
              case AskQuestion(rsMsgErrEOpen + ': ' + SourceFile.FullPath, '',
                               [fsourRetry, fsourSkip, fsourSkipAll, fsourAbort],
                               fsourRetry, fsourSkip) of
                fsourRetry:
                  bRetry := True;
                fsourAbort:
                  AbortOperation;
                fsourSkip: ; // Do nothing
                fsourSkipAll:
                  FSkipOpenForReadingError := True;
              end;
            end;
          end;
      end;
    end;
    if not Assigned(SourceFileStream) and (log_errors in gLogOptions) then
      logWrite(FOperationThread, rsMsgLogError + rsMsgErrEOpen + ': ' + SourceFile.FullPath, lmtError, True);
  end;

  procedure OpenTargetFile;
    function GetMsgByMode: String;
    begin
      if Mode in [fsohcmAppend, fsohcmResume] then
        Result := rsMsgErrEOpen
      else
        Result := rsMsgErrECreate;
    end;
    function HandleError: Boolean;
    begin
      Result := False;
      if not FSkipOpenForWritingError then
      begin
        case AskQuestion(GetMsgByMode + ': ' + TargetFileName, '',
                         [fsourRetry, fsourSkip, fsourSkipAll, fsourAbort],
                         fsourRetry, fsourSkip) of
          fsourRetry:
            Result := True;
          fsourAbort:
            AbortOperation;
          fsourSkip: ; // Do nothing
          fsourSkipAll:
            FSkipOpenForWritingError := True;
        end;
      end;
    end;
  var
    bRetry: Boolean = True;
  begin
    while bRetry do
    begin
      bRetry := False;
      try
        TargetFileStream.Free; // In case stream was created but 'while' loop run again
        case Mode of
        fsohcmAppend:
          begin
            TargetFileStream := TFileStreamEx.Create(TargetFileName, fmOpenReadWrite);
            TargetFileStream.Seek(0, soFromEnd); // seek to end
            TotalBytesToRead := SourceFileStream.Size;
          end;
        fsohcmResume:
          begin
            TargetFileStream := TFileStreamEx.Create(TargetFileName, fmOpenReadWrite);
            NewPos := TargetFileStream.Seek(0, soFromEnd);
            SourceFileStream.Seek(NewPos, soFromBeginning);
            TotalBytesToRead := SourceFileStream.Size - NewPos;
          end
        else
          begin
            TargetFileStream := TFileStreamEx.Create(TargetFileName, fmCreate);
            TotalBytesToRead := SourceFileStream.Size;
            if FReserveSpace then
            begin
              TargetFileStream.Size:= SourceFileStream.Size;
              TargetFileStream.Seek(0, fsFromBeginning);
            end;
          end;
        end;
      except
        on EFOpenError do
          bRetry := HandleError;
        on EFCreateError do
          bRetry := HandleError;
      end;
    end;
    if not Assigned(TargetFileStream) and (log_errors in gLogOptions) then
      logWrite(FOperationThread, rsMsgLogError + GetMsgByMode + ': ' + TargetFileName, lmtError, True);
  end;
begin
  Result := False;

  { Check disk free space }
  if FCheckFreeSpace = True then
  begin
    GetDiskFreeSpace(ExtractFilePath(TargetFileName), iFreeDiskSize, iTotalDiskSize);
    if SourceFile.Size > iFreeDiskSize then
    begin
      if FSkipAllBigFiles = True then
      begin
        Exit;
      end
      else
      begin
        case AskQuestion('', rsMsgNoFreeSpaceCont,
                         [fsourYes, fsourAll, fsourNo, fsourSkip, fsourSkipAll],
                         fsourYes, fsourNo) of
          fsourNo:
            AbortOperation;

          fsourSkip:
            Exit;

          fsourAll:
            FCheckFreeSpace := False;

          fsourSkipAll:
            begin
              FSkipAllBigFiles := True;
              Exit;
            end;
        end;
      end;
    end;
  end;

  BytesToRead := FBufferSize;
  SourceFileStream := nil;
  TargetFileStream := nil; // for safety exception handling
  try
    try
      OpenSourceFile;
      if not Assigned(SourceFileStream) then
        Exit;

      OpenTargetFile;
      if not Assigned(TargetFileStream) then
        Exit;

      while TotalBytesToRead > 0 do
      begin
        // Without the following line the reading is very slow
        // if it tries to read past end of file.
        if TotalBytesToRead < BytesToRead then
          BytesToRead := TotalBytesToRead;

        repeat
          try
            bRetryRead := False;
            BytesRead := SourceFileStream.Read(FBuffer^, BytesToRead);

            if (BytesRead = 0) then
              Raise EReadError.Create(mbSysErrorMessage(GetLastOSError));

            TotalBytesToRead := TotalBytesToRead - BytesRead;
            BytesWritten := 0;

            repeat
              try
                bRetryWrite := False;
                BytesWrittenTry := TargetFileStream.Write((FBuffer + BytesWritten)^, BytesRead);
                BytesWritten := BytesWritten + BytesWrittenTry;
                if BytesWrittenTry = 0 then
                begin
                  Raise EWriteError.Create(mbSysErrorMessage(GetLastOSError));
                end
                else if BytesWritten < BytesRead then
                begin
                  bRetryWrite := True;   // repeat and try to write the rest
                end;
              except
                on E: EWriteError do
                  begin
                    { Check disk free space }
                    GetDiskFreeSpace(ExtractFilePath(TargetFileName), iFreeDiskSize, iTotalDiskSize);
                    if BytesRead > iFreeDiskSize then
                      begin
                        case AskQuestion(rsMsgNoFreeSpaceRetry, '',
                                         [fsourYes, fsourNo, fsourSkip],
                                         fsourYes, fsourNo) of
                          fsourYes:
                            bRetryWrite := True;
                          fsourNo:
                            AbortOperation;
                          fsourSkip:
                            Exit;
                        end; // case
                      end
                    else
                      begin
                        DeleteFile := FSkipWriteError and not (Mode in [fsohcmAppend, fsohcmResume]);
                        if FSkipWriteError then Exit;
                        case AskQuestion(rsMsgErrEWrite + ' ' + TargetFileName + ':',
                                         E.Message,
                                         [fsourRetry, fsourSkip, fsourSkipAll, fsourAbort],
                                         fsourRetry, fsourSkip) of
                          fsourRetry:
                            bRetryWrite := True;
                          fsourAbort:
                            AbortOperation;
                          fsourSkip:
                            Exit;
                          fsourSkipAll:
                            begin
                              DeleteFile := not (Mode in [fsohcmAppend, fsohcmResume]);
                              FSkipWriteError := True;
                              Exit;
                            end;
                        end; // case
                      end;

                  end; // on do
              end; // except
            until not bRetryWrite;
          except
            on E: EReadError do
              begin
                DeleteFile := FSkipReadError and not (Mode in [fsohcmAppend, fsohcmResume]);
                if FSkipReadError then Exit;
                case AskQuestion(rsMsgErrERead + ' ' + SourceFile.FullPath + ':',
                                 E.Message,
                                 [fsourRetry, fsourSkip, fsourSkipAll, fsourAbort],
                                 fsourRetry, fsourSkip) of
                  fsourRetry:
                    bRetryRead := True;
                  fsourAbort:
                    AbortOperation;
                  fsourSkip:
                    Exit;
                  fsourSkipAll:
                    begin
                      DeleteFile := not (Mode in [fsohcmAppend, fsohcmResume]);
                      FSkipReadError := True;
                      Exit;
                    end;
                end; // case
              end;
          end;
        until not bRetryRead;

        with FStatistics do
        begin
          CurrentFileDoneBytes := CurrentFileDoneBytes + BytesRead;
          DoneBytes := DoneBytes + BytesRead;

          UpdateStatistics(FStatistics);
        end;

        CheckOperationState; // check pause and stop
      end;//while

      Result:= True;

    except
      on EFileSourceOperationAborting do
      begin
        // Always delete file when user aborted operation.
        DeleteFile := True;
        raise;
      end;
    end;

  finally
    FreeAndNil(SourceFileStream);
    if Assigned(TargetFileStream) then
    begin
      FreeAndNil(TargetFileStream);
      if TotalBytesToRead > 0 then
      begin
        // There was some error, because not all of the file has been copied.
        // Ask if delete the not completed target file.
        if DeleteFile or
           (AskQuestion('', rsMsgDeletePartiallyCopied,
                        [fsourYes, fsourNo], fsourYes, fsourNo) = fsourYes) then
        begin
          mbDeleteFile(TargetFileName);
        end;
      end;
    end;
  end;

  CopyProperties(SourceFile.FullPath, TargetFileName);
end;

procedure TFileSystemOperationHelper.CopyProperties(SourceFileName, TargetFileName: String);
var
  CopyAttrResult: TCopyAttributesOptions;
  Msg: String = '';
begin
  if FCopyAttributesOptions <> [] then
  begin
    CopyAttrResult := mbFileCopyAttr(SourceFileName, TargetFileName, FCopyAttributesOptions);
    if CopyAttrResult <> [] then
    begin
      case FSetPropertyError of
        fsoospeIgnoreErrors: ; // Do nothing
        fsoospeDontSet:
          FCopyAttributesOptions := FCopyAttributesOptions - CopyAttrResult;
        fsoospeNone:
          begin
            if caoCopyAttributes in CopyAttrResult then
              AddStrWithSep(Msg, Format(rsMsgErrSetAttribute, [SourceFileName]), LineEnding);
            if caoCopyTime in CopyAttrResult then
              AddStrWithSep(Msg, Format(rsMsgErrSetDateTime, [SourceFileName]), LineEnding);
            if caoCopyOwnership in CopyAttrResult then
              AddStrWithSep(Msg, Format(rsMsgErrSetOwnership, [SourceFileName]), LineEnding);

            case AskQuestion(Msg, '',
                             [fsourSkip, fsourSkipAll, fsourIgnoreAll, fsourAbort],
                             fsourSkip, fsourIgnoreAll) of
              //fsourSkip: do nothing
              fsourSkipAll:
                // Don't set properties that failed to be set anymore.
                FCopyAttributesOptions := FCopyAttributesOptions - CopyAttrResult;
              fsourIgnoreAll:
                FSetPropertyError := fsoospeIgnoreErrors;
              fsourAbort:
                AbortOperation;
            end;
          end
        else
          Assert(False, 'Invalid TFileSourceOperationOptionSetPropertyError value.');
      end;
    end;
  end;
end;

function TFileSystemOperationHelper.MoveFile(SourceFile: TFile; TargetFileName: String;
  Mode: TFileSystemOperationHelperCopyMode): Boolean;
begin
  if (Mode in [fsohcmAppend, fsohcmResume]) or
     (not mbRenameFile(SourceFile.FullPath, TargetFileName)) then
  begin
    if CopyFile(SourceFile, TargetFileName, Mode) then
    begin
      if FileIsReadOnly(SourceFile.Attributes) then
        mbFileSetReadOnly(SourceFile.FullPath, False);
      Result := mbDeleteFile(SourceFile.FullPath)
    end
    else
      Result := False;
  end
  else
    Result := True;
end;

function TFileSystemOperationHelper.ProcessNode(aFileTreeNode: TFileTreeNode;
                                                CurrentTargetPath: String): Boolean;
var
  aFile: TFile;
  ProcessedOk: Boolean;
  TargetName: String;
  CurrentFileIndex: Integer;
  CurrentSubNode: TFileTreeNode;
begin
  Result := True;

  for CurrentFileIndex := 0 to aFileTreeNode.SubNodesCount - 1 do
  begin
    CurrentSubNode := aFileTreeNode.SubNodes[CurrentFileIndex];
    aFile := CurrentSubNode.TheFile;

    if FRenamingRootDir and (aFile = FRootDir) then
      TargetName := CurrentTargetPath + FRenameMask
    else if FRenamingFiles then
      TargetName := CurrentTargetPath + ApplyRenameMask(aFile, FRenameNameMask, FRenameExtMask)
    else
      TargetName := CurrentTargetPath + aFile.Name;

    with FStatistics do
    begin
      CurrentFileFrom := aFile.FullPath;
      CurrentFileTo := TargetName;
      CurrentFileTotalBytes := aFile.Size;
      CurrentFileDoneBytes := 0;
    end;

    UpdateStatistics(FStatistics);

    // Check if moving to the same file.
    if mbSameFile(TargetName, aFile.FullPath) then
    begin
      if (FMode = fsohmCopy) and FAutoRenameItSelf then
        TargetName := GetNextCopyName(TargetName)
      else
        case AskQuestion(Format(rsMsgCanNotCopyMoveItSelf, [TargetName]), '',
                         [fsourAbort, fsourSkip], fsourAbort, fsourSkip) of
          fsourAbort:
            AbortOperation();
        else
            begin
              Result := False;
              CountStatistics(CurrentSubNode);
              CheckOperationState;
              Continue;
            end;
        end;
    end;
    if aFile.IsDirectory then
      ProcessedOk := ProcessDirectory(CurrentSubNode, TargetName)
    else if aFile.IsLink then
      ProcessedOk := ProcessLink(CurrentSubNode, TargetName)
    else
      ProcessedOk := ProcessFile(CurrentSubNode, TargetName);

    if not ProcessedOk then
      Result := False;

    CheckOperationState;
  end;
end;

function TFileSystemOperationHelper.ProcessDirectory(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;
var
  bRemoveDirectory: Boolean;
  NodeData: TFileTreeNodeData;
begin
  NodeData := aNode.Data as TFileTreeNodeData;

  // If some files will not be moved then source directory cannot be deleted.
  bRemoveDirectory := (FMode = fsohmMove) and (NodeData.SubnodesHaveExclusions = False);

  case TargetExists(aNode, AbsoluteTargetFileName) of
    fsoterSkip:
      begin
        Result := False;
        CountStatistics(aNode);
      end;

    fsoterDeleted, fsoterNotExists:
      begin
        // Try moving whole directory tree. It can be done only if we don't have
        // to process each subnode: if there are no links, or they're not being
        // processed, if the files are not being renamed or excluded.
        if (FMode = fsohmMove) and
           (not FRenamingFiles) and
           ((FCorrectSymlinks = False) or (NodeData.SubnodesHaveLinks = False)) and
           (NodeData.SubnodesHaveExclusions = False) and
           mbRenameFile(aNode.TheFile.FullPath, AbsoluteTargetFileName) then
        begin
          // Success.
          CountStatistics(aNode);
          Result := True;
          bRemoveDirectory := False;
        end
        else
        begin
          // Create target directory.
          if mbCreateDir(AbsoluteTargetFileName) then
          begin
            // Copy/Move all files inside.
            Result := ProcessNode(aNode, IncludeTrailingPathDelimiter(AbsoluteTargetFileName));
            // Copy attributes after copy/move directory contents, because this operation can change date/time
            CopyProperties(aNode.TheFile.FullPath, AbsoluteTargetFileName);
          end
          else
          begin
            // Error - all files inside not copied/moved.
            ShowError(rsMsgLogError + Format(rsMsgErrForceDir, [AbsoluteTargetFileName]));
            Result := False;
            CountStatistics(aNode);
          end;
        end;
      end;

    fsoterAddToTarget:
      begin
        // Don't create existing directory, but copy files into it.
        Result := ProcessNode(aNode, IncludeTrailingPathDelimiter(AbsoluteTargetFileName));
      end;

    else
      raise Exception.Create('Invalid TargetExists result');
  end;

  if bRemoveDirectory and Result then
  begin
    if FileIsReadOnly(aNode.TheFile.Attributes) then
      mbFileSetReadOnly(aNode.TheFile.FullPath, False);
    mbRemoveDir(aNode.TheFile.FullPath);
  end;
end;

function TFileSystemOperationHelper.ProcessLink(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;
var
  LinkTarget, CorrectedLink: String;
  aFile: TFile;
  aSubNode: TFileTreeNode;
begin
  Result := True;

  // If link was followed then it's target is stored in a subnode.
  if aNode.SubNodesCount > 0 then
  begin
    aSubNode := aNode.SubNodes[0];
    //DCDebug('Link ' + aFile.FullPath + ' followed to '
    //        + (aSubNode.TheFile as TFileSystemFile).FullPath
    //        + ' will be copied as: ' + AbsoluteTargetFileName);
    if aSubNode.TheFile.AttributesProperty.IsDirectory then
      Result := ProcessDirectory(aSubNode, AbsoluteTargetFileName)
    else
      Result := ProcessFile(aSubNode, AbsoluteTargetFileName);

    Exit; // exit without counting statistics, because they are not counted for followed links
  end;

  aFile := aNode.TheFile;

  case TargetExists(aNode, AbsoluteTargetFileName) of
    fsoterSkip:
      Result := False;

    fsoterDeleted, fsoterNotExists:
      begin
        if (FMode <> fsohmMove) or
           (not mbRenameFile(aFile.FullPath, AbsoluteTargetFileName)) then
        begin
          LinkTarget := ReadSymLink(aFile.FullPath);     // use sLinkTo ?
          if LinkTarget <> '' then
          begin
            if FCorrectSymlinks then
            begin
              CorrectedLink := GetAbsoluteFileName(aFile.Path, LinkTarget);

              // If the link was relative - make also the corrected link relative.
              if GetPathType(LinkTarget) = ptRelative then
                LinkTarget := ExtractRelativepath(AbsoluteTargetFileName, CorrectedLink)
              else
                LinkTarget := CorrectedLink;
            end;

            if CreateSymlink(LinkTarget, AbsoluteTargetFileName) then
            begin
              CopyProperties(aFile.FullPath, AbsoluteTargetFileName);
            end
            else
            begin
              ShowError(rsMsgLogError + Format(rsMsgLogSymLink, [AbsoluteTargetFileName]));
              Result := False;
            end;
          end
          else
          begin
            DCDebug('Error reading link');
            Result := False;
          end;
        end;
      end;

    fsoterAddToTarget:
      raise Exception.Create('Cannot add to link');

    else
      raise Exception.Create('Invalid TargetExists result');
  end;

  Inc(FStatistics.DoneFiles);
  UpdateStatistics(FStatistics);
end;

function TFileSystemOperationHelper.ProcessFile(aNode: TFileTreeNode; AbsoluteTargetFileName: String): Boolean;
var
  OldDoneBytes: Int64; // for if there was an error
begin
  Result:= False;

  // If there will be an error the DoneBytes value
  // will be inconsistent, so remember it here.
  OldDoneBytes := FStatistics.DoneBytes;

  if (aNode.TheFile.Size > GetDiskMaxFileSize(ExtractFileDir(AbsoluteTargetFileName))) then
    case AskQuestion('', Format(rsMsgFileSizeTooBig, [aNode.TheFile.Name]),
                     [fsourSkip, fsourAbort],
                     fsourSkip, fsourAbort) of
      fsourSkip:
        Result := False;
      else
        AbortOperation;
    end
  else
    case TargetExists(aNode, AbsoluteTargetFileName) of
      fsoterSkip:
        Result := False;

      fsoterDeleted, fsoterNotExists:
        Result := MoveOrCopy(aNode.TheFile, AbsoluteTargetFileName, fsohcmDefault);

      fsoterAddToTarget:
        Result := MoveOrCopy(aNode.TheFile, AbsoluteTargetFileName, fsohcmAppend);

      fsoterResume:
        Result := MoveOrCopy(aNode.TheFile, AbsoluteTargetFileName, fsohcmResume);

      else
        raise Exception.Create('Invalid TargetExists result');
    end;

  if Result = True then
    begin
      LogMessage(Format(rsMsgLogSuccess+FLogCaption, [aNode.TheFile.FullPath + ' -> ' + AbsoluteTargetFileName]),
                 [log_cp_mv_ln], lmtSuccess);

      // process comments if need
      if gProcessComments then
      begin
        case FMode of
          fsohmCopy:
            FDescription.CopyDescription(aNode.TheFile.FullPath, AbsoluteTargetFileName);
          fsohmMove:
            FDescription.MoveDescription(aNode.TheFile.FullPath, AbsoluteTargetFileName);
        end;
      end;
    end
  else
    begin
      LogMessage(Format(rsMsgLogError+FLogCaption, [aNode.TheFile.FullPath + ' -> ' + AbsoluteTargetFileName]),
                 [log_cp_mv_ln], lmtError);
    end;

  with FStatistics do
  begin
    DoneFiles := DoneFiles + 1;
    DoneBytes := OldDoneBytes + aNode.TheFile.Size;
    UpdateStatistics(FStatistics);
  end;
end;

// ----------------------------------------------------------------------------

function TFileSystemOperationHelper.TargetExists(aNode: TFileTreeNode;
  var AbsoluteTargetFileName: String): TFileSystemOperationTargetExistsResult;
var
  Attrs, LinkTargetAttrs: TFileAttrs;
  SourceFile: TFile;

  function DoDirectoryExists(AllowCopyInto: Boolean; AllowDeleteDirectory: Boolean): TFileSystemOperationTargetExistsResult;
  begin
    case DirExists(SourceFile, AbsoluteTargetFileName, AllowCopyInto, AllowDeleteDirectory) of
      fsoodeSkip:
        Exit(fsoterSkip);
      fsoodeDelete:
        begin
          if FPS_ISLNK(Attrs) then
            mbDeleteFile(AbsoluteTargetFileName)
          else
            DelTree(AbsoluteTargetFileName);
          Exit(fsoterDeleted);
        end;
      fsoodeCopyInto:
        begin
          Exit(fsoterAddToTarget);
        end;
      else
        raise Exception.Create('Invalid dir exists option');
    end;
  end;

  function DoFileExists(AllowAppend: Boolean): TFileSystemOperationTargetExistsResult;
  begin
    case FileExists(SourceFile, AbsoluteTargetFileName, AllowAppend) of
      fsoofeSkip:
        Exit(fsoterSkip);
      fsoofeOverwrite:
        begin
          if FileIsReadOnly(Attrs) then
            mbFileSetReadOnly(AbsoluteTargetFileName, False);
          if FPS_ISLNK(Attrs) or (FMode = fsohmMove) then
          begin
            mbDeleteFile(AbsoluteTargetFileName);
            Exit(fsoterDeleted);
          end;
          Exit(fsoterNotExists);
        end;
      fsoofeAppend:
        begin
          Exit(fsoterAddToTarget);
        end;
      fsoofeResume:
        begin
          Exit(fsoterResume);
        end;
      fsoofeAutoRenameSource:
        begin
          Exit(fsoterNotExists);
        end
      else
        raise Exception.Create('Invalid file exists option');
    end;
  end;

  function IsLinkFollowed: Boolean;
  begin
    // If link was followed then it's target is stored in a subnode.
    Result := SourceFile.AttributesProperty.IsLink and (aNode.SubNodesCount > 0);
  end;

  function AllowAppendFile: Boolean;
  begin
    Result := (not SourceFile.AttributesProperty.IsDirectory) and (not FReserveSpace) and
              ((not SourceFile.AttributesProperty.IsLink) or
               (IsLinkFollowed and (not aNode.SubNodes[0].TheFile.AttributesProperty.IsDirectory)));
  end;

  function AllowCopyInto: Boolean;
  begin
    Result := SourceFile.AttributesProperty.IsDirectory or
              (IsLinkFollowed and aNode.SubNodes[0].TheFile.IsDirectory);
  end;

  function AllowDeleteDirectory: Boolean;
  begin
    Result := (not (SourceFile.AttributesProperty.IsDirectory or
                   (IsLinkFollowed and aNode.SubNodes[0].TheFile.IsDirectory))) or
              gOverwriteFolder;
  end;

begin
  Attrs := mbFileGetAttr(AbsoluteTargetFileName);
  if Attrs <> faInvalidAttributes then
  begin
    SourceFile := aNode.TheFile;

    // Target exists - ask user what to do.
    if FPS_ISDIR(Attrs) then
    begin
      Result := DoDirectoryExists(AllowCopyInto, AllowDeleteDirectory)
    end
    else if FPS_ISLNK(Attrs) then
    begin
      // Check if target of the link exists.
      LinkTargetAttrs := mbFileGetAttrNoLinks(AbsoluteTargetFileName);
      if (LinkTargetAttrs <> faInvalidAttributes) then
      begin
        if FPS_ISDIR(LinkTargetAttrs) then
          Result := DoDirectoryExists(AllowCopyInto, AllowDeleteDirectory)
        else
          Result := DoFileExists(AllowAppendFile);
      end
      else
        // Target of link doesn't exist. Treat link as file and don't allow append.
        Result := DoFileExists(False);
    end
    else
      // Existing target is a file.
      Result := DoFileExists(AllowAppendFile);
  end
  else
    Result := fsoterNotExists;
end;

function TFileSystemOperationHelper.DirExists(
             aFile: TFile;
             AbsoluteTargetFileName: String;
             AllowCopyInto: Boolean;
             AllowDelete: Boolean): TFileSourceOperationOptionDirectoryExists;
var
  PossibleResponses: array of TFileSourceOperationUIResponse = nil;
  DefaultOkResponse: TFileSourceOperationUIResponse;

  procedure AddResponse(Response: TFileSourceOperationUIResponse);
  begin
    SetLength(PossibleResponses, Length(PossibleResponses) + 1);
    PossibleResponses[Length(PossibleResponses) - 1] := Response;
  end;

begin
  case FDirExistsOption of
    fsoodeNone:
      begin
        if AllowDelete then
          AddResponse(fsourOverwrite);
        if AllowCopyInto then
        begin
          AddResponse(fsourCopyInto);
          AddResponse(fsourCopyIntoAll);
        end;
        AddResponse(fsourSkip);
        if AllowDelete then
          AddResponse(fsourOverwriteAll);
        AddResponse(fsourSkipAll);
        AddResponse(fsourCancel);

        if AllowCopyInto then
          DefaultOkResponse := fsourCopyInto
        else if AllowDelete then
          DefaultOkResponse := fsourOverwrite
        else
          DefaultOkResponse := fsourSkip;

        case AskQuestion(Format(rsMsgFolderExistsRwrt, [AbsoluteTargetFileName]), '',
                         PossibleResponses, DefaultOkResponse, fsourSkip) of
          fsourOverwrite:
            Result := fsoodeDelete;
          fsourCopyInto:
            Result := fsoodeCopyInto;
          fsourCopyIntoAll:
            begin
              FDirExistsOption := fsoodeCopyInto;
              Result := fsoodeCopyInto;
            end;
          fsourSkip:
            Result := fsoodeSkip;
          fsourOverwriteAll:
            begin
              FDirExistsOption := fsoodeDelete;
              Result := fsoodeDelete;
            end;
          fsourSkipAll:
            begin
              FDirExistsOption := fsoodeSkip;
              Result := fsoodeSkip;
            end;
          fsourNone,
          fsourCancel:
            AbortOperation;
        end;
      end;

    else
      Result := FDirExistsOption;
  end;
end;

function TFileSystemOperationHelper.FileExists(aFile: TFile;
  var AbsoluteTargetFileName: String; AllowAppend: Boolean
  ): TFileSourceOperationOptionFileExists;
const
  Responses: array[0..11] of TFileSourceOperationUIResponse
    = (fsourOverwrite, fsourSkip, fsourRenameSource, fsourOverwriteAll,
       fsourSkipAll, fsourResume, fsourOverwriteOlder, fsourCancel, fsourAppend,
       fsourOverwriteSmaller, fsourOverwriteLarger, fsourAutoRenameSource);
  ResponsesNoAppend: array[0..9] of TFileSourceOperationUIResponse
    = (fsourOverwrite, fsourSkip, fsourRenameSource,  fsourOverwriteAll,
       fsourSkipAll, fsourOverwriteSmaller, fsourOverwriteOlder, fsourCancel,
       fsourOverwriteLarger, fsourAutoRenameSource);
var
  Answer: Boolean;
  Message: String;
  PossibleResponses: array of TFileSourceOperationUIResponse;

  function OverwriteOlder: TFileSourceOperationOptionFileExists;
  begin
    if aFile.ModificationTime > FileTimeToDateTime(mbFileAge(AbsoluteTargetFileName)) then
      Result := fsoofeOverwrite
    else
      Result := fsoofeSkip;
  end;

  function OverwriteSmaller: TFileSourceOperationOptionFileExists;
  begin
    if aFile.Size > mbFileSize(AbsoluteTargetFileName) then
      Result := fsoofeOverwrite
    else
      Result := fsoofeSkip;
  end;

  function OverwriteLarger: TFileSourceOperationOptionFileExists;
  begin
    if aFile.Size < mbFileSize(AbsoluteTargetFileName) then
      Result := fsoofeOverwrite
    else
      Result := fsoofeSkip;
  end;

begin
  case FFileExistsOption of
    fsoofeNone:
      repeat
        Answer := True;
        case AllowAppend of
          True :  PossibleResponses := Responses;
          False:  PossibleResponses := ResponsesNoAppend;
        end;
        Message:= FileExistsMessage(AbsoluteTargetFileName, aFile.FullPath,
                                    aFile.Size, aFile.ModificationTime);
        case AskQuestion(Message, '',
                         PossibleResponses, fsourOverwrite, fsourSkip) of
          fsourOverwrite:
            Result := fsoofeOverwrite;
          fsourSkip:
            Result := fsoofeSkip;
          fsourAppend:
            begin
              //FFileExistsOption := fsoofeAppend; - for AppendAll
              Result := fsoofeAppend;
            end;
          fsourResume:
            begin
              Result := fsoofeResume;
            end;
          fsourOverwriteAll:
            begin
              FFileExistsOption := fsoofeOverwrite;
              Result := fsoofeOverwrite;
            end;
          fsourSkipAll:
            begin
              FFileExistsOption := fsoofeSkip;
              Result := fsoofeSkip;
            end;
          fsourOverwriteOlder:
            begin
              FFileExistsOption := fsoofeOverwriteOlder;
              Result:= OverwriteOlder;
            end;
          fsourOverwriteSmaller:
            begin
              FFileExistsOption := fsoofeOverwriteSmaller;
              Result:= OverwriteSmaller;
            end;
          fsourOverwriteLarger:
            begin
              FFileExistsOption := fsoofeOverwriteLarger;
              Result:= OverwriteLarger;
            end;
          fsourAutoRenameSource:
            begin
              Result:= fsoofeAutoRenameSource;
              FFileExistsOption:= fsoofeAutoRenameSource;
              AbsoluteTargetFileName:= GetNextCopyName(AbsoluteTargetFileName);
            end;
          fsourRenameSource:
            begin
              Message:= ExtractFileName(AbsoluteTargetFileName);
              Answer:= ShowInputQuery(FOperationThread, Application.Title, rsEditNewFileName, Message);
              if Answer then
              begin
                Result:= fsoofeAutoRenameSource;
                AbsoluteTargetFileName:= ExtractFilePath(AbsoluteTargetFileName) + Message;
              end;
            end;
          fsourNone,
          fsourCancel:
            AbortOperation;
        end;
        until Answer;
    fsoofeOverwriteOlder:
      begin
        Result:= OverwriteOlder;
      end;
    fsoofeOverwriteSmaller:
      begin
        Result:= OverwriteSmaller;
      end;
    fsoofeOverwriteLarger:
      begin
        Result:= OverwriteLarger;
      end;
    fsoofeAutoRenameSource:
      begin
        Result:= fsoofeAutoRenameSource;
        AbsoluteTargetFileName:= GetNextCopyName(AbsoluteTargetFileName);
      end;

    else
      Result := FFileExistsOption;
  end;
end;

procedure TFileSystemOperationHelper.ShowError(sMessage: String);
begin
  if gSkipFileOpError then
  begin
    if log_errors in gLogOptions then
      logWrite(FOperationThread, sMessage, lmtError, True);
  end
  else
  begin
    if AskQuestion(sMessage, '', [fsourSkip, fsourAbort],
                   fsourSkip, fsourAbort) <> fsourSkip then
    begin
      AbortOperation;
    end;
  end;
end;

procedure TFileSystemOperationHelper.LogMessage(sMessage: String; logOptions: TLogOptions; logMsgType: TLogMsgType);
begin
  case logMsgType of
    lmtError:
      if not (log_errors in gLogOptions) then Exit;
    lmtInfo:
      if not (log_info in gLogOptions) then Exit;
    lmtSuccess:
      if not (log_success in gLogOptions) then Exit;
  end;

  if logOptions <= gLogOptions then
  begin
    logWrite(FOperationThread, sMessage, logMsgType);
  end;
end;

procedure TFileSystemOperationHelper.CountStatistics(aNode: TFileTreeNode);
  procedure CountNodeStatistics(aNode: TFileTreeNode);
  var
    aFileAttrs: TFileAttributesProperty;
    i: Integer;
  begin
    aFileAttrs := aNode.TheFile.AttributesProperty;

    with FStatistics do
    begin
      if aFileAttrs.IsDirectory then
      begin
        // No statistics for directory.
        // Go through subdirectories.
        for i := 0 to aNode.SubNodesCount - 1 do
          CountNodeStatistics(aNode.SubNodes[i]);
      end
      else if aFileAttrs.IsLink then
      begin
        // Count only not-followed links.
        if aNode.SubNodesCount = 0 then
          DoneFiles := DoneFiles + 1
        else
          // Count target of link.
          CountNodeStatistics(aNode.SubNodes[0]);
      end
      else
      begin
        // Count files.
        DoneFiles := DoneFiles + 1;
        DoneBytes := DoneBytes + aNode.TheFile.Size;
      end;
    end;
  end;

begin
  CountNodeStatistics(aNode);
  UpdateStatistics(FStatistics);
end;

end.

