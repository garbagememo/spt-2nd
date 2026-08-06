program ScaleOBJ;

{$mode objfpc}{$H+}
{$codepage utf8} // ← これを追加！

uses
{$ifdef unix}
   cwstring, // ← Linux/Unix環境でUTF-8(System/WideString)を正しく扱うために必須
{$endif}
   SysUtils;

var
  InFile, OutFile: TextFile;
  InputPath, OutputPath: string;
  Line, NewLine, Trimmed: string;
  ScaleFactor: Double;
  FS: TFormatSettings;
  VertexCount: Int64 = 0;
  Tokens: TStringArray;
  i: Integer;
  Val: Double;

begin
  // 1. コマンドライン引数の確認
  if ParamCount < 3 then
  begin
    WriteLn('使用方法: ', ExtractFileName(ParamStr(0)), ' <入力ファイル.obj> <出力ファイル.obj> <倍率N>');
    WriteLn('実行例:   ', ExtractFileName(ParamStr(0)), ' input.obj output.obj 2.5');
    Halt(1);
  end;

  InputPath := ParamStr(1);
  OutputPath := ParamStr(2);

  // OBJフォーマット用に小数点を '.' に固定
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';

  // 倍率のパース
  if not TryStrToFloat(ParamStr(3), ScaleFactor, FS) then
  begin
    WriteLn('エラー: 指定された倍率「', ParamStr(3), '」は有効な数値ではありません。');
    Halt(1);
  end;

  if not FileExists(InputPath) then
  begin
    WriteLn('エラー: 入力ファイル「', InputPath, '」が見つかりません。');
    Halt(1);
  end;

  // 2. ファイルのオープン
  AssignFile(InFile, InputPath);
  AssignFile(OutFile, OutputPath);
  
  {$I-}
  Reset(InFile);
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('エラー: 入力ファイルを開けませんでした。');
    Halt(1);
  end;

  {$I-}
  Rewrite(OutFile);
  {$I+}
  if IOResult <> 0 then
  begin
    CloseFile(InFile);
    WriteLn('エラー: 出力ファイルを作成できませんでした。');
    Halt(1);
  end;

  WriteLn('処理を開始します... (倍率: ', ScaleFactor:0:4, ')');

  // 3. 行ごとの処理
  while not Eof(InFile) do
  begin
    ReadLn(InFile, Line);
    Trimmed := Trim(Line);

    // 先頭が 'v' かつ、その直後が空白/タブであるか判定 (vn や vt を除外)
    if (Length(Trimmed) >= 2) and (Trimmed[1] = 'v') and ((Trimmed[2] = ' ') or (Trimmed[2] = #9)) then
    begin
      // 空白・タブでトークン分割
      Tokens := Trimmed.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
      
      if (Length(Tokens) >= 4) and (Tokens[0] = 'v') then
      begin
        NewLine := 'v';
        
        for i := 1 to High(Tokens) do
        begin
          // 最初の3つの数値 (X, Y, Z) のみ N 倍処理
          if (i <= 3) and TryStrToFloat(Tokens[i], Val, FS) then
          begin
            Val := Val * ScaleFactor;
            NewLine := NewLine + ' ' + FloatToStr(Val, FS);
          end
          else
          begin
            // 4つ目以降要素（W座標やRGBカラー値が含まれる場合）はそのまま維持
            NewLine := NewLine + ' ' + Tokens[i];
          end;
        end;

        WriteLn(OutFile, NewLine);
        Inc(VertexCount);
        Continue;
      end;
    end;

    // 頂点以外の行（面情報 f、法線 vn、コメント等）は変更せずに書き出し
    WriteLn(OutFile, Line);
  end;

  // 4. 後処理
  CloseFile(InFile);
  CloseFile(OutFile);

  WriteLn('完了しました！');
  WriteLn('拡大・縮小した頂点数: ', VertexCount);
  WriteLn('出力先: ', OutputPath);
end.
