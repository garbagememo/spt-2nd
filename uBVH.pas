unit uBVH;
{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}

interface
uses uVect,uShape,Math,Classes;
const
  Nil_Leaf=-1;
type
  IntegerArray=array of integer;

  BVHNodeClass=Class
    root:AABBRecord;
    left,right:BVHNodeClass;
    leaf:integer;
    constructor Create(var ary: IntegerArray; L, R: Integer; sph: TList);
    function intersect(r:RayRecord;sph:TList):HitInfo;
  end;

//procedure AABBSort(var a: array of integer;sph:TList);
   
implementation


function GetAABBVal(suf:integer;axis:integer;sph:TList):real;
begin
  case axis of
    1:result:=ShapeClass(sph[suf]).BoundBox.little.x;
    2:result:=ShapeClass(sph[suf]).BoundBox.little.y;
    else begin
      result:=ShapeClass(sph[suf]).BoundBox.little.z;
    end;
  end ;(*case*)
end;

// クイックソート用の内部処理関数
procedure QuickSortAABBInternal(var vals: array of real; var a: array of integer; L, R: integer);
var
  I, J, TmpA: integer;
  Pivot, TmpVal: real;
begin
  repeat
    I := L;
    J := R;
    Pivot := vals[(L + R) div 2];
    repeat
      while vals[I] < Pivot do Inc(I);
      while vals[J] > Pivot do Dec(J);
      if I <= J then begin
        // キャッシュ値の入れ替え
        TmpVal := vals[I]; vals[I] := vals[J]; vals[J] := TmpVal;
        // 元のインデックス配列の入れ替え
        TmpA := a[I]; a[I] := a[J]; a[J] := TmpA;
        Inc(I);
        Dec(J);
      end;
    until I > J;
    if L < J then QuickSortAABBInternal(vals, a, L, J);
    L := I;
  until I >= R;
end;

procedure AABBSort(var a: array of integer; sph: TList);
var
  i, axis: integer;
  ar: real;
  vals: array of real;
begin
  if Length(a) <= 1 then Exit;

  // 1. 軸の決定
  ar := random;
  if ar < 0.33 then axis := 1 
  else if ar < 0.67 then axis := 2 
  else axis := 3;

  // 2. GetAABBVal の事前計算
  SetLength(vals, Length(a));
  for i := 0 to High(a) do
    vals[i] := GetAABBVal(a[i], axis, sph);

  // 3. ジェネリクスを使わない自作クイックソートを実行
  QuickSortAABBInternal(vals, a, 0, High(a));
end;

// インターフェース / 呼び出し用手続き
procedure AABBSortRange(var a: array of integer; L, R, axis: integer; sph: TList);
var
  i: integer;
  vals: array of real;
begin
  // ソート対象の要素が1つ以下の場合は何もしない
  if (R - L) <= 0 then Exit;

  // 1. 指定範囲 (L..R) の GetAABBVal を事前計算してキャッシュ
  SetLength(vals, Length(a));
  for i := L to R do
    vals[i] := GetAABBVal(a[i], axis, sph);

  // 2. 指定範囲のみを対象にクイックソートを実行
  QuickSortAABBInternal(vals, a, L, R);
end;


// 開始位置 L と 終了位置 R を受け取る形式に変更
constructor BVHNodeClass.Create(var ary: IntegerArray; L, R: Integer; sph: TList);
var
  i, mid, axis: integer;
  axisWidth: Vec3;
begin
  Leaf := Nil_Leaf;
  
  // 1. 全要素を包み込む AABB を計算 (ShapeClassに修正)
  root := ShapeClass(sph[ary[L]]).BoundBox;
  for i := L + 1 to R do
    root := root.MargeBoundBox(ShapeClass(sph[ary[i]]).BoundBox);

  // 2. 葉ノードの判定（要素数が1個、または数個以下なら葉にする）
  if (R - L + 1) = 1 then
  begin
    Leaf := ary[L];
    Left := nil;
    Right := nil;
    Exit;
  end;

  // 3. 最長軸の決定（ランダムではなく AABB の幅で選ぶ）
  axisWidth := root.large - root.little;
  if (axisWidth.x >= axisWidth.y) and (axisWidth.x >= axisWidth.z) then
    axis := 1
  else if (axisWidth.y >= axisWidth.x) and (axisWidth.y >= axisWidth.z) then
    axis := 2
  else
    axis := 3;

  // 4. 指定範囲のみソート（AABBSortRange などを作成）
  AABBSortRange(ary, L, R, axis, sph);

  // 5. 中間位置で分割して再帰呼び出し（配列コピーなし）
  mid := (L + R) div 2;
  Left := BVHNodeClass.Create(ary, L, mid, sph);
  Right := BVHNodeClass.Create(ary, mid + 1, R, sph);
end;

function BVHnodeClass.intersect(r:RayRecord;sph:TList):HitInfo;
var
   RIR,LIR:HitInfo;
   Info:InterInfo;
begin
   result.isHit:=false;
   result.t:=INF;
   result.id:=0;
   if leaf<>Nil_Leaf then begin
      Info:=ShapeClass(sph[leaf]).intersect(r);
      result.t:=Info.t;
      if result.t<INF then begin
         result.id:=Leaf;
         result.isHit:=true;
      end;
      exit;
   end;

   if root.Hit(r,EPS,INF) then begin
      RIR:=Right.intersect(r,sph);
      LIR:=Left.intersect(r,sph);
      if (LIR.isHit or RIR.isHit) then begin
         if RIR.isHit then result:=RIR;
         if LIR.isHit then begin
            if RIR.isHit=false then
               result:=LIR
            else if RIR.t>LIR.t then
               result:=LIR;
         end;
      end;
   end
   else begin
      result.isHit:=false;
      result.t:=INF;
   end;
end;

begin
end.
