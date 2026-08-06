unit uVect;
{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}
{$codepage utf8} // ← これを追加！

interface

uses
{$ifdef unix}
   cwstring, // ← Linux/Unix環境でUTF-8(System/WideString)を正しく扱うために必須
{$endif}
   sysutils,uBMP,math;

const
   MAX_WORD = High(WORD);
   eps=1e-4;
   INF=1e20;

type
    Vec3=record
        x,y,z:real;
        function new(x_,y_,z_:real):Vec3;
        function Norm:Vec3;inline;
        function len:real;inline;
        function Dot(const V2 :Vec3):real;inline;//内積
        function Cross(const V2 :Vec3):Vec3;inline;//外積
        function Mult(const V2:Vec3):Vec3;inline;
        function Neg:Vec3;
        class operator * (const v1: Vec3; const r: real): Vec3; inline;
        class operator / (const v1: Vec3; const r: real): Vec3; inline;
        class operator * (const v1, v2: Vec3): real; inline; // 内積
        class operator / (const v1, v2: Vec3): Vec3; inline; // 外積
        class operator + (const v1, v2: Vec3): Vec3; inline;
        class operator - (const v1, v2: Vec3): Vec3; inline;
        class operator + (const v1: Vec3; const r: real): Vec3; inline;
        class operator - (const v1: Vec3; const r: real): Vec3; inline;        
    end;
    RayRecord=record
       o, d:Vec3;
       function new(o_,d_:Vec3):RayRecord;
    end;
    
   CamRecord=record
      o,d:Vec3;
      PlaneDist:real;
      w,h,samps:integer;
      cx,cy:Vec3;
      function new(o_,d_:Vec3;w_,h_,samps_:integer):CamRecord;
      function GetRay(x,y,sx,sy:integer):RayRecord;
      procedure CamWrite;
   end;
   
   function ClampVector(v:Vec3):Vec3;
   function ColToRGB(v:Vec3):rgbColor;
const
   BackGroundColor:Vec3 = (x:0;y:0;z:0);
   ZeroVec:Vec3 = (x:0;y:0;z:0);
   INFVec:Vec3=(x:INF*2;y:INF*2;z:INF*2);
   DefaultPosition:Vec3=(x:50.0; y:52.0; z:295.6);
   DefaultDirection:Vec3=(x:0.0; y:-0.042612; z:-1.0);

function VecAdd3(V1,V2,V3:Vec3):Vec3;
procedure VecWriteln(V:Vec3);
procedure WriteVec(v:Vec3);
function isINF(v:Vec3):boolean;

implementation

function isINF(v:Vec3):boolean;
begin
   if (v.x>INF) and (v.y>INF) and (v.z>INF) then result := true else result:=false;
end;

function Vec3.new(x_,y_,z_:real):Vec3;inline;
begin
   x:=x_;y:=y_;z:=z_;
   result:=self;
end;

function Vec3.Norm:Vec3;inline;
begin
   result:=self/sqrt(x*x+y*y+z*z);
end;

function Vec3.len:real;inline;
begin
   result:=sqrt(x*x+y*y+z*z);
end;

function Vec3.Dot(const V2 :Vec3):real;inline;//内積
begin
    result:=x*v2.x+y*v2.y+z*v2.z;
end;

function Vec3.Cross(const V2 :Vec3):Vec3;inline;//外積
begin
    result.x:=y * v2.z - v2.y * z;
    result.y:=z * v2.x - v2.z * x;
    result.z:=x * v2.y - v2.x * y;
end;

function Vec3.Mult(const V2:Vec3):Vec3;inline;
begin
    result.x:=x*V2.x;
    result.y:=y*V2.y;
    result.z:=z*V2.z;
end;

function Vec3.Neg:Vec3;
begin
    result.x:=-x;
    result.y:=-y;
    result.z:=-z;
end;

function RayRecord.new(o_,d_:Vec3):RayRecord;
begin
   o:=o_;
   d:=d_;
   result:=self;
end;

function VecAdd3(V1,V2,V3:Vec3):Vec3;
begin
    result.x:=V1.x+V2.x+V3.x;
    result.y:=V1.y+V2.y+V3.y;
    result.z:=V1.z+V2.z+V3.z;
end;

procedure VecWriteln(V:Vec3);
begin
    writeln(v.x:7:3,':',v.y:7:3,':',v.z:7:3);
end;

procedure WriteVec(v:Vec3);
begin
   write('(',v.x:7:3,':',v.y:7:3,':',v.z:7:3,')');
end;

class operator Vec3.* (const v1: Vec3; const r: real): Vec3; inline;
begin
   result.x := v1.x * r;
   result.y := v1.y * r;
   result.z := v1.z * r;
end;

class operator Vec3./ (const v1: Vec3; const r: real): Vec3; inline;
begin
   result.x := v1.x / r;
   result.y := v1.y / r;
   result.z := v1.z / r;
end;

class operator Vec3.* (const v1, v2: Vec3): real; inline; // 内積
begin
   result := v1.x * v2.x + v1.y * v2.y + v1.z * v2.z;
end;

class operator Vec3./ (const v1, v2: Vec3): Vec3; inline; // 外積
begin
   result.x := v1.y * v2.z - v2.y * v1.z;
   result.y := v1.z * v2.x - v2.z * v1.x;
   result.z := v1.x * v2.y - v2.x * v1.y;
end;

class operator Vec3.+ (const v1, v2: Vec3): Vec3; inline;
begin
   result.x := v1.x + v2.x;
   result.y := v1.y + v2.y;
   result.z := v1.z + v2.z;
end;

class operator Vec3.- (const v1, v2: Vec3): Vec3; inline;
begin
   result.x := v1.x - v2.x;
   result.y := v1.y - v2.y;
   result.z := v1.z - v2.z;
end;

class operator Vec3.+ (const v1: Vec3; const r: real): Vec3; inline;
begin
   result.x := v1.x + r;
   result.y := v1.y + r;
   result.z := v1.z + r;
end;

class operator Vec3.- (const v1: Vec3; const r: real): Vec3; inline;
begin
   result.x := v1.x - r;
   result.y := v1.y - r;
   result.z := v1.z - r;
end;

function Clamp(x:real):real;inline;
begin
   if x<0 then exit(0);
   if x>1 then exit(1);
   exit(x);
end;

function ClampVector(v:Vec3):Vec3;
begin
  result.x:=clamp(v.x);
  result.y:=clamp(v.y);
  result.z:=clamp(v.z);
end;

function ColToWord(x:real):Word;inline;
begin
    result:=trunc(power(x,1/2.2)* MAX_WORD +0.5);
end;

function ColToRGB(v:Vec3):rgbColor;
begin
    result.r:=ColToWord(v.x);
    result.g:=ColToWord(v.y);
    result.b:=ColToWord(v.z);
end;

function CamRecord.new(o_,d_:Vec3;w_,h_,samps_:integer):CamRecord;
begin
  o:=o_;d:=d_;w:=w_;h:=h_;samps:=samps_;
  cx.new(w * 0.5135 / h, 0, 0);
  cy:= (cx/ d).norm* 0.5135;
  PlaneDist:=140;
  result:=self;
end;

function CamRecord.GetRay(x,y,sx,sy:integer):RayRecord;
var
   r1,r2,dx,dy:real;
   dirct:Vec3;
begin
   r1 := 2 * random;
   if (r1 < 1) then
      dx := sqrt(r1) - 1
   else
      dx := 1 - sqrt(2 - r1);
   r2 := 2 * random;
   if (r2 < 1) then
      dy := sqrt(r2) - 1
   else
      dy := 1 - sqrt(2 - r2);
   dirct:= cy* (((sy + 0.5 + dy) / 2 + (h - y - 1)) / h - 0.5)
      +cx* (((sx + 0.5 + dx) / 2 + x) / w - 0.5)
      +d;
   dirct:=dirct.norm;
   result.o:= dirct* PlaneDist+o;
   result.d := dirct;
end;

procedure CamRecord.CamWrite;
var
   r:RayRecord;
begin
   write(' o=');VecWriteln(o);
   write(' d=');VecWriteln(d);
   write(' cx=');VecWriteln(cx);
   write(' cy=');VecWriteln(cy);
   writeln('===0,0==');
   r:=GetRay(0,0,0,0);
   write(' r.o=');VecWriteln(r.o);
   write(' r.d=');VecWriteln(r.d);
   writeln('===320,240==');
   r:=GetRay(320,240,0,0);
   write(' r.o=');VecWriteln(r.o);
   write(' r.d=');VecWriteln(r.d);
end;

  
begin
end.
   
