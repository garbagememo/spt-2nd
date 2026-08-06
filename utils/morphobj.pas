program TransformObjCLI;

{$mode objfpc}{$H+}
{$codepage utf8} // ← これを追加！


uses
  SysUtils, Classes, GetOpts;

procedure PrintHelp;
begin
  Writeln('使用方法: ', ExtractFileName(ParamStr(0)), ' -i <input.obj> -o <output.obj> [オプション]');
  Writeln;
  Writeln('オプション:');
  Writeln('  -i, --input  <file>    入力OBJファイル（必須）');
  Writeln('  -o, --output <file>    出力OBJファイル（必須）');
  Writeln('  -s, --scale  <number>  拡大縮小倍率 (デフォルト: 1.0)');
  Writeln('  -x, --transx <number>  X方向の移動量 (デフォルト: 0.0)');
  Writeln('  -y, --transy <number>  Y方向の移動量 (デフォルト: 0.0)');
  Writeln('  -z, --transz <number>  Z方向の移動量 (デフォルト: 0.0)');
  Writeln('  -h, --help            ヘルプの表示');
end;

procedure TransformObjFile(const InputFilePath, OutputFilePath: string;
  Scale: Double; TransX, TransY, TransZ: Double);
var
  InFile, OutFile: TextFile;
  Line: string;
  Parts: TStringArray;
  X, Y, Z: Double;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  AssignFile(InFile, InputFilePath);
  Reset(InFile);
  AssignFile(OutFile, OutputFilePath);
  Rewrite(OutFile);

  try
    while not EOF(InFile) do
    begin
      Readln(InFile, Line);
      Line := Trim(Line);

      if (Length(Line) >= 2) and (Copy(Line, 1, 2) = 'v ') then
      begin
        Parts := Line.Split([' '], TStringSplitOptions.ExcludeEmpty);
        if Length(Parts) >= 4 then
        begin
          if TryStrToFloat(Parts[1], X, FS) and
             TryStrToFloat(Parts[2], Y, FS) and
             TryStrToFloat(Parts[3], Z, FS) then
          begin
            X := (X * Scale) + TransX;
            Y := (Y * Scale) + TransY;
            Z := (Z * Scale) + TransZ;

            if Length(Parts) >= 5 then
              Writeln(OutFile, Format('v %.6f %.6f %.6f %s', [X, Y, Z, Parts[4]], FS))
            else
              Writeln(OutFile, Format('v %.6f %.6f %.6f', [X, Y, Z], FS));
            Continue;
          end;
        end;
      end;
      Writeln(OutFile, Line);
    end;
  finally
    CloseFile(InFile);
    CloseFile(OutFile);
  end;
end;

var
  InputFile, OutputFile: string;
  ScaleFactor, MoveX, MoveY, MoveZ: Double;
  C: Char;
  LongIndex: LongInt;
  FS: TFormatSettings;
  
const
  // ロングオプションの定義
  LongOpts: array[1..7] of TOption = (
    (Name: 'input';  Has_arg: Required_Argument; Flag: nil; Value: 'i'),
    (Name: 'output'; Has_arg: Required_Argument; Flag: nil; Value: 'o'),
    (Name: 'scale';  Has_arg: Required_Argument; Flag: nil; Value: 's'),
    (Name: 'transx'; Has_arg: Required_Argument; Flag: nil; Value: 'x'),
    (Name: 'transy'; Has_arg: Required_Argument; Flag: nil; Value: 'y'),
    (Name: 'transz'; Has_arg: Required_Argument; Flag: nil; Value: 'z'),
    (Name: 'help';   Has_arg: No_Argument;       Flag: nil; Value: 'h')
  );

begin
  InputFile   := '';
  OutputFile  := '';
  ScaleFactor := 1.0;
  MoveX       := 0.0;
  MoveY       := 0.0;
  MoveZ       := 0.0;

  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // コマンドライン引数の解析
  repeat
    C := GetLongOpts('i:o:s:x:y:z:h', @LongOpts[1], LongIndex);
    case C of
      'i': InputFile := OptArg;
      'o': OutputFile := OptArg;
      's': TryStrToFloat(OptArg, ScaleFactor, FS);
      'x': TryStrToFloat(OptArg, MoveX, FS);
      'y': TryStrToFloat(OptArg, MoveY, FS);
      'z': TryStrToFloat(OptArg, MoveZ, FS);
      'h', '?':
        begin
          PrintHelp;
          Halt(0);
        end;
    end;
  until C = EndOfOptions;

  // 必須入力の検証
  if (InputFile = '') or (OutputFile = '') then
  begin
    Writeln('エラー: -i (入力) および -o (出力) パラメータは必須です。');
    Writeln;
    PrintHelp;
    Halt(1);
  end;

  if not FileExists(InputFile) then
  begin
    Writeln('エラー: ファイルが存在しません: ', InputFile);
    Halt(1);
  end;

  Writeln('OBJファイルを変換しています...');
  TransformObjFile(InputFile, OutputFile, ScaleFactor, MoveX, MoveY, MoveZ);
  Writeln('完了しました。');
end.
