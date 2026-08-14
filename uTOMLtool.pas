unit uTOMLtool;

interface

{$mode objfpc}{$H+}{$M+}
{$codepage UTF8}

uses
   {$IFDEF UNIX}
   cthreads,cmem,
   cwstring,
   {$ENDIF}
   {$IFDEF WINDOWS}
   Windows,
   {$ENDIF}
   SysUtils, Classes, StrUtils, Generics.Collections,uVect,uShape,uRadiance;


type
  TOMLValueType = (tvtNil, tvtString, tvtInteger, tvtFloat, tvtBoolean, tvtArray, tvtTable);

  TOMLTable = class;
  TOMLArray = class;

  { TOMLValue: TOML内の任意の値を保持するクラス }
  TOMLValue = class
  private
    FValueType: TOMLValueType;
    FStrVal: String;
    FIntVal: Int64;
    FFloatVal: Double;
    FBoolVal: Boolean;
    FArrayVal: TOMLArray;
    FTableVal: TOMLTable;
  public
    constructor Create; overload;
    constructor CreateString(const AValue: String); overload;
    constructor CreateInt(AValue: Int64); overload;
    constructor CreateFloat(AValue: Double); overload;
    constructor CreateBool(AValue: Boolean); overload;
    constructor CreateArray; overload;
    constructor CreateTable; overload;
    destructor Destroy; override;

    property ValueType: TOMLValueType read FValueType;
    property AsString: String read FStrVal;
    property AsInt: Int64 read FIntVal;
    property AsFloat: Double read FFloatVal;
    property AsBool: Boolean read FBoolVal;
    property AsArray: TOMLArray read FArrayVal;
    property AsTable: TOMLTable read FTableVal;
  end;

  { TOMLTable: キーと値（TOMLValue）のマップ }
  TOMLTable = class
  private
    FDict: specialize TObjectDictionary<String, TOMLValue>;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(const AKey: String; AValue: TOMLValue);
    function Find(const AKey: String): TOMLValue;
    function GetTable(const AKey: String): TOMLTable;
    function GetArray(const AKey: String): TOMLArray;

    function GetString(const AKey: String; const ADefault: String = ''): String;
    function GetInt(const AKey: String; const ADefault: Int64 = 0): Int64;
    function GetFloat(const AKey: String; const ADefault: Double = 0.0): Double;
    function GetBool(const AKey: String; const ADefault: Boolean = False): Boolean;

    property Items[const AKey: String]: TOMLValue read Find; default;
    property Dict: specialize TObjectDictionary<String, TOMLValue> read FDict;
  end;

  { TOMLArray: TOMLValueのリスト（配列） }
  TOMLArray = class
  private
    FList: specialize TObjectList<TOMLValue>;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TOMLValue;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Add(AValue: TOMLValue);
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TOMLValue read GetItem; default;
  end;

  { TOMLDocument: TOMLドキュメント全体をパース・管理するクラス }
  TOMLDocument = class
  private
    FRoot: TOMLTable;

    function StripComment(const ALine: String): String;
    function SplitArrayElements(const AContent: String): TStringList;
    function ParseValue(const AValStr: String): TOMLValue;
    function GetOrCreateTable(ARootTable: TOMLTable; const APath: String): TOMLTable;
    function GetOrCreateArrayTable(ARootTable: TOMLTable; const APath: String): TOMLTable;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure LoadFromString(const AContent: String);
    procedure LoadFromFile(const AFileName: String);
    // GetValueByPath('camera.width'): ドット区切りのパス表記による値の参照にも対応しています。
    function GetValueByPath(const APath: String): TOMLValue;

    property Root: TOMLTable read FRoot;
  end;

type
   SPTOMLDocument=class(TOMLDocument)
   private
      FBVHCount:integer;
      FBVHVal:TOMLValue;
   public
      constructor create(FN:string);
      function CamNew:CamRecord;
      function KeyToVec3(KeyName:string):Vec3;
      function ObjKeyToVec3(OT:TOMLtable;KeyName:string):Vec3;
      function GetShapeList:ShapeListClass;
      procedure GetBVHListArray;
      function GetBVHList(i:integer):BVHListClass;
      procedure AddBVHList(var sc:SceneRecord);
      property BVHCount:integer read FBVHCount;
   end;

  
implementation

{ TOMLValue Implementation }

constructor TOMLValue.Create;
begin
  inherited Create;
  FValueType := tvtNil;
end;

constructor TOMLValue.CreateString(const AValue: String);
begin
  Create;
  FValueType := tvtString;
  FStrVal := AValue;
end;

constructor TOMLValue.CreateInt(AValue: Int64);
begin
  Create;
  FValueType := tvtInteger;
  FIntVal := AValue;
end;

constructor TOMLValue.CreateFloat(AValue: Double);
begin
  Create;
  FValueType := tvtFloat;
  FFloatVal := AValue;
end;

constructor TOMLValue.CreateBool(AValue: Boolean);
begin
  Create;
  FValueType := tvtBoolean;
  FBoolVal := AValue;
end;

constructor TOMLValue.CreateArray;
begin
  Create;
  FValueType := tvtArray;
  FArrayVal := TOMLArray.Create;
end;

constructor TOMLValue.CreateTable;
begin
  Create;
  FValueType := tvtTable;
  FTableVal := TOMLTable.Create;
end;

destructor TOMLValue.Destroy;
begin
  if FValueType = tvtArray then FreeAndNil(FArrayVal)
  else if FValueType = tvtTable then FreeAndNil(FTableVal);
  inherited Destroy;
end;

{ TOMLTable Implementation }

constructor TOMLTable.Create;
begin
  inherited Create;
  // doOwnsValues によりテーブル破棄時に子オブジェクトを自動解放
  FDict := specialize TObjectDictionary<String, TOMLValue>.Create([doOwnsValues]);
end;

destructor TOMLTable.Destroy;
begin
  FDict.Free;
  inherited Destroy;
end;

procedure TOMLTable.Add(const AKey: String; AValue: TOMLValue);
begin
   FDict.AddOrSetValue(LowerCase(AKey), AValue);
end;

function TOMLTable.Find(const AKey: String): TOMLValue;
begin
   if not FDict.TryGetValue(LowerCase(AKey), Result) then
      Result := nil;
end;

function TOMLTable.GetTable(const AKey: String): TOMLTable;
var
   V: TOMLValue;
begin
   V := Find(AKey);
   if (V <> nil) and (V.ValueType = tvtTable) then Result := V.AsTable
   else Result := nil;
end;

function TOMLTable.GetArray(const AKey: String): TOMLArray;
var
   V: TOMLValue;
begin
   V := Find(AKey);
   if (V <> nil) and (V.ValueType = tvtArray) then Result := V.AsArray
   else Result := nil;
end;

function TOMLTable.GetString(const AKey: String; const ADefault: String): String;
var
   V: TOMLValue;
begin
   V := Find(AKey);
   if (V <> nil) and (V.ValueType = tvtString) then Result := V.AsString else Result := ADefault;
end;

function TOMLTable.GetInt(const AKey: String; const ADefault: Int64): Int64;
var
   V: TOMLValue;
begin
  V := Find(AKey);
  if (V <> nil) and (V.ValueType = tvtInteger) then Result := V.AsInt else Result := ADefault;
end;

function TOMLTable.GetFloat(const AKey: String; const ADefault: Double): Double;
var
   V: TOMLValue;
begin
   V := Find(AKey);
   if V <> nil then begin
      if V.ValueType = tvtFloat then Exit(V.AsFloat);
      if V.ValueType = tvtInteger then Exit(V.AsInt);
   end;
   Result := ADefault;
end;

function TOMLTable.GetBool(const AKey: String; const ADefault: Boolean): Boolean;
var
   V: TOMLValue;
begin
   V := Find(AKey);
   if (V <> nil) and (V.ValueType = tvtBoolean) then Result := V.AsBool else Result := ADefault;
end;

{ TOMLArray Implementation }

constructor TOMLArray.Create;
begin
   inherited Create;
   FList := specialize TObjectList<TOMLValue>.Create(True);
end;

destructor TOMLArray.Destroy;
begin
   FList.Free;
   inherited Destroy;
end;

procedure TOMLArray.Add(AValue: TOMLValue);
begin
  FList.Add(AValue);
end;

function TOMLArray.GetCount: Integer;
begin
   Result := FList.Count;
end;

function TOMLArray.GetItem(AIndex: Integer): TOMLValue;
begin
   Result := FList[AIndex];
end;

{ TOMLDocument Implementation }

constructor TOMLDocument.Create;
begin
   inherited Create;
   FRoot := TOMLTable.Create;
end;

destructor TOMLDocument.Destroy;
begin
   FRoot.Free;
   inherited Destroy;
end;

procedure TOMLDocument.Clear;
begin
   FRoot.Free;
   FRoot := TOMLTable.Create;
end;

// クォート外のコメント（# ...）を除去
function TOMLDocument.StripComment(const ALine: String): String;
var
   I: Integer;
   InQuote: Boolean;
   QuoteChar: Char;
begin
   InQuote := False;
   QuoteChar := #0;
   for I := 1 to Length(ALine) do begin
      if (ALine[I] = '"') or (ALine[I] = '''') then begin
         if not InQuote then begin InQuote := True; QuoteChar := ALine[I]; end
         else if ALine[I] = QuoteChar then InQuote := False;
      end
      else if (ALine[I] = '#') and not InQuote then
         Exit(Copy(ALine, 1, I - 1));
   end;
   Result := ALine;
end;

// インライン配列 [1, 2, 3] 内の要素分割処理
function TOMLDocument.SplitArrayElements(const AContent: String): TStringList;
var
   I, BracketDepth: Integer;
   Ch, QuoteChar: Char;
   InQuote: Boolean;
   CurToken: String;
begin
   Result := TStringList.Create;
   InQuote := False; QuoteChar := #0; BracketDepth := 0; CurToken := '';

   for I := 1 to Length(AContent) do begin
      Ch := AContent[I];
      if InQuote then begin
         CurToken := CurToken + Ch;
         if Ch = QuoteChar then InQuote := False;
      end
      else begin
         if (Ch = '"') or (Ch = '''') then begin InQuote := True; QuoteChar := Ch; CurToken := CurToken + Ch; end
         else if (Ch = '[') or (Ch = '{') then begin Inc(BracketDepth); CurToken := CurToken + Ch; end
         else if (Ch = ']') or (Ch = '}') then begin Dec(BracketDepth); CurToken := CurToken + Ch; end
         else if (Ch = ',') and (BracketDepth = 0) then begin Result.Add(Trim(CurToken)); CurToken := ''; end
         else CurToken := CurToken + Ch;
      end;
   end;
   if Trim(CurToken) <> '' then Result.Add(Trim(CurToken));
end;

// 文字列値を解析して TOMLValue に変換
function TOMLDocument.ParseValue(const AValStr: String): TOMLValue;
var
   S, SubStr: String;
   FS: TFormatSettings;
   IntVal: Int64;
   FloatVal: Double;
   ArrVal: TOMLValue;
   ElemStrings: TStringList;
   I: Integer;
begin
   FS := DefaultFormatSettings;
   FS.DecimalSeparator := '.';
   S := Trim(AValStr);

   // 文字列 ("..." または '...')
   if (Length(S) >= 2) and (((S[1] = '"') and (S[Length(S)] = '"')) or ((S[1] = '''') and (S[Length(S)] = ''''))) then
      Exit(TOMLValue.CreateString(Copy(S, 2, Length(S) - 2)));

   // ブール値
   if SameText(S, 'true') then Exit(TOMLValue.CreateBool(True));
   if SameText(S, 'false') then Exit(TOMLValue.CreateBool(False));

   // 配列 [...]
   if (Length(S) >= 2) and (S[1] = '[') and (S[Length(S)] = ']') then begin
      SubStr := Trim(Copy(S, 2, Length(S) - 2));
      ArrVal := TOMLValue.CreateArray;
      if SubStr <> '' then begin
         ElemStrings := SplitArrayElements(SubStr);
         try
            for I := 0 to ElemStrings.Count - 1 do
               ArrVal.AsArray.Add(ParseValue(ElemStrings[I]));
         finally
            ElemStrings.Free;
         end;
      end;
      Exit(ArrVal);
   end;

   // 整数値
   if TryStrToInt64(S, IntVal) then Exit(TOMLValue.CreateInt(IntVal));

   // 浮動小数点数
   if TryStrToFloat(S, FloatVal, FS) then Exit(TOMLValue.CreateFloat(FloatVal));

   // フォールバック（クォートなし文字列など）
   Result := TOMLValue.CreateString(S);
end;

function TOMLDocument.GetOrCreateTable(ARootTable: TOMLTable; const APath: String): TOMLTable;
var
   Parts: TStringArray;
   I: Integer;
   Key: String;
   NextVal: TOMLValue;
   Target: TOMLTable;
begin
   Parts := APath.Split(['.']);
   Target := ARootTable;
   for I := 0 to High(Parts) do begin
      Key := Trim(Parts[I]);
      NextVal := Target.Find(Key);
      if NextVal = nil then begin
         NextVal := TOMLValue.CreateTable;
         Target.Add(Key, NextVal);
      end;
      Target := NextVal.AsTable;
   end;
   Result := Target;
end;

function TOMLDocument.GetOrCreateArrayTable(ARootTable: TOMLTable; const APath: String): TOMLTable;
var
   Parts: TStringArray;
   I: Integer;
   ParentPath, ArrayKey: String;
   ParentTable: TOMLTable;
   ArrVal, NewTableVal: TOMLValue;
begin
   Parts := APath.Split(['.']);
   if Length(Parts) = 1 then begin
      ParentTable := ARootTable;
      ArrayKey := Trim(Parts[0]);
   end
   else begin
      ParentPath := '';
      for I := 0 to High(Parts) - 1 do begin
         if I > 0 then ParentPath := ParentPath + '.';
         ParentPath := ParentPath + Parts[I];
      end;
      ParentTable := GetOrCreateTable(ARootTable, ParentPath);
      ArrayKey := Trim(Parts[High(Parts)]);
   end;

   ArrVal := ParentTable.Find(ArrayKey);
   if ArrVal = nil then begin
      ArrVal := TOMLValue.CreateArray;
      ParentTable.Add(ArrayKey, ArrVal);
   end;

   NewTableVal := TOMLValue.CreateTable;
   ArrVal.AsArray.Add(NewTableVal);
   Result := NewTableVal.AsTable;
end;

procedure TOMLDocument.LoadFromString(const AContent: String);
var
   Lines: TStringList;
   I, J, EqPos: Integer;
   Line, Key, Val, CurrentSection, SubPath: String;
   CurTable, TargetTable: TOMLTable;
   Parts: TStringArray;
begin
   Clear;
   Lines := TStringList.Create;
   try
      Lines.Text := AContent;
      CurrentSection := '';
      CurTable := FRoot;

      for I := 0 to Lines.Count - 1 do begin
         Line := Trim(StripComment(Lines[I]));
         if Line = '' then Continue;

         // 配列テーブル形式 [[section.name]]
         if StartsText('[[', Line) and EndsText(']]', Line) then begin
            CurrentSection := Copy(Line, 3, Length(Line) - 4);
            CurTable := GetOrCreateArrayTable(FRoot, CurrentSection);
            Continue;
         end;

         // 通常テーブル形式 [section.name]
         if StartsText('[', Line) and EndsText(']', Line) then begin
            CurrentSection := Copy(Line, 2, Length(Line) - 2);
            CurTable := GetOrCreateTable(FRoot, CurrentSection);
            Continue;
         end;

         // Key = Value
         EqPos := Pos('=', Line);
         if EqPos > 0 then begin
            Key := Trim(Copy(Line, 1, EqPos - 1));
            Val := Trim(Copy(Line, EqPos + 1, Length(Line) - EqPos));

            // ドット記法 (例: ring.inner_radius = 10.0) のサポート
            Parts := Key.Split(['.']);
            if Length(Parts) > 1 then begin
               SubPath := '';
               for J := 0 to High(Parts) - 1 do begin
                  if J > 0 then SubPath := SubPath + '.';
                  SubPath := SubPath + Trim(Parts[J]);
               end;
               TargetTable := GetOrCreateTable(CurTable, SubPath);
               TargetTable.Add(Trim(Parts[High(Parts)]), ParseValue(Val));
            end else begin
               CurTable.Add(Key, ParseValue(Val));
            end;
         end;
      end;
   finally
      Lines.Free;
   end;
end;

procedure TOMLDocument.LoadFromFile(const AFileName: String);
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.LoadFromFile(AFileName);
    LoadFromString(List.Text);
  finally
    List.Free;
  end;
end;

// GetValueByPath('camera.width'): ドット区切りのパス表記による値の参照にも対応しています。
function TOMLDocument.GetValueByPath(const APath: String): TOMLValue;
var
  Parts: TStringArray;
  I: Integer;
  CurTable: TOMLTable;
begin
  Parts := APath.Split(['.']);
  CurTable := FRoot;
  for I := 0 to High(Parts) - 1 do begin
    CurTable := CurTable.GetTable(Parts[I]);
    if CurTable = nil then Exit(nil);
  end;
  Result := CurTable.Find(Parts[High(Parts)]);
end;

//===============以下SPT対応部分==========
constructor SPTOMLDocument.create(FN:string);
begin
   inherited create;
   LoadFromFile(FN);
end;

function SPTOMLDocument.KeyToVec3(KeyName:string):Vec3;
var
   Val:TOMLValue;
   PosArray: TOMLArray;
begin
   Val := GetValueByPath(KeyName);
   if (Val <> nil) and (Val.ValueType = tvtArray) then begin
      PosArray := Val.AsArray;
      result.new( PosArray[0].AsFloat,PosArray[1].AsFloat,PosArray[2].AsFloat);
   end
   else
      result:=INFVec;
end;

function SPTOMLDocument.ObjKeyToVec3(OT:TOMLtable;KeyName:string):Vec3;
var
   PosArray:TOMLArray;
begin
   PosArray := OT.GetArray(KeyName);
   if (PosArray <> nil) then 
      result.new( PosArray[0].AsFloat,PosArray[1].AsFloat,PosArray[2].AsFloat);
end;      

function SPTOMLDocument.GetShapeList:ShapeListClass;
var
   ObjArrayVal: TOMLValue;
   ObjTable,TextureTable: TOMLTable;
   i: integer;
   ShapeList:ShapeListClass;
   sh:ShapeClass;
   r:real;c,e,p:Vec3;refl:RefType;
begin
   // 'objects' 全体の配列を取得
   ObjArrayVal := GetValueByPath('objects');

   if (ObjArrayVal <> nil) and (ObjArrayVal.ValueType = tvtArray) then begin
      ShapeList:=ShapeListClass.Create;
      
      WriteLn('オブジェクト総数: ', ObjArrayVal.AsArray.Count);

      for i:=0 to ObjArrayVal.AsArray.Count-1 do begin
         ObjTable := ObjArrayVal.AsArray[i].AsTable;
         if ObjTable.GetString('shape')='sphere' then begin
            r:=ObjTable.GetFloat('radius');
            p:=ObjKeyToVec3(ObjTable,'position');
            e:=ObjKeyToVec3(ObjTable,'emission');
            c:=ObjKeyToVec3(ObjTable,'color');
            refl:=StrToRefl(ObjTable.GetString('material') );
            sh:=SphereClass.Create(r,p,e,c,refl);
            if ObjTable.GetString('texture')<>'' then begin
               TextureTable := ObjTable.GetTable('ring');
               if TextureTable <> nil  then begin
                  sh.tx:=RingTextureClass.create(e,c,
                                                 ObjKeyToVec3(TextureTable,'center'),
                                                 ObjKeyToVec3(TextureTable,'modify'));
               end;
               TextureTable := ObjTable.GetTable('bmp');
               if TextureTable<>nil then begin
                  sh.tx:=SphereBMPTextureClass.create(e,c,SphereClass(sh).p,
                                                      ObjFilePath,
                                                      TextureTable.GetString('filename'));
                  end;
            end;            
            ShapeList.add(sh );
         end
         else if ObjTable.GetString('shape')='obj' then begin
            ShapeList.LoadObj(ObjFilePath,ObjTable.GetString('filename') );
         end;
      end;
      result:=ShapeList;
   end
   else begin
      result:=nil;
   end;
end;

procedure SPTOMLDocument.GetBVHListArray;
begin
      // 'BVH' 全体の配列を取得
   FBVHVal := GetValueByPath('BVH');

   if (FBVHVal <> nil) and (FBVHVal.ValueType = tvtArray) then begin
      WriteLn('BVHオブジェクト総数: ', FBVHVal.AsArray.Count);
      FBVHCount:=FBVHVal.AsArray.Count;
   end
   else begin
      FBVHVal:=nil;
      FBVHCount:=0;
   end;   
end;

function SPTOMLDocument.GetBVHList(i:integer):BVHListClass;
var
   ObjTable:TOMLTable;
   bvh:BVHListClass;
begin
   if (i<0) or (i>FBVHCount-1) then begin result:=nil; exit;end;
   ObjTable := FBVHVal.AsArray[i].AsTable;
   if ObjTable.GetString('shape')='obj' then begin
      bvh:=BVHListClass.Create;
      bvh.LoadObj(ObjFilePath,ObjTable.GetString('filename') );
      result:=bvh; 
   end;
end;

procedure SPTOMLDocument.AddBVHList(var sc:SceneRecord);
var
   i:integer;
begin
   GetBVHListArray;
   for i:=0 to BVHCount-1 do sc.scList.add(GetBVHList(i));
end;

function SPTOMLDocument.CamNew:CamRecord;
var
   cam:CamRecord;
   w,h,samps:integer;
   o,d:Vec3;
   dist:real;
   Val:TOMLValue;
begin
   Val := GetValueByPath('camera.width');
   if Val<>nil then w:=Val.asInt else w:=640;
   Val := GetValueByPath('camera.height');     
   if Val<>nil then h:=Val.asInt else h:=480;
   Val := GetValueByPath('camera.samples');     
   if Val<>nil then samps:=Val.asInt else samps:=16;
   Val := GetValueByPath('camera.plane_distancet');     
   if Val<>nil then dist:=Val.asFloat else dist:=140;

   o:=KeyToVec3('camera.position');
   if isINF(o) then o:=DefaultPosition;
   
   d:=KeyToVec3('camera.direction');
   if isINF(d) then d:=DefaultDirection;
   result:=cam.new(o,d,w,h,samps);
   cam.PlaneDist:=dist;
end;

begin
end.
