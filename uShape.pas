unit uShape;
{$MODE objfpc}{$H+}
{$INLINE ON}
{$modeswitch advancedrecords}

interface
uses SysUtils,Classes,uVect,uBMP,Math;

type
   RefType=(DIFF,SPEC,REFR);// material types, used in radiance()
   {
    DIFFUSE,    // 完全拡散面。いわゆるLambertian面。
    SPECULAR,   // 理想的な鏡面。
    REFRACTION, // 理想的なガラス的物質。
   }
   TraceInfo = record
      cpc:real;//反射・屈折pdf
      r:RayRecord;
   end;
   
   MaterialClass = class
      function GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;virtual;abstract;
      function IDStr:string;virtual;
   end;

   DiffuseClass = class(MaterialClass)
      function GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;override;
      function IDStr:string;override;
   end;

   MirrorClass = class(MaterialClass)
      function GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;override;
      function IDStr:string;override;
   end;

   RefractClass = class(MaterialClass)
      function GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;override;
      function IDStr:string;override;
   end;

   TextureClass = class
      e,c:Vec3;
      constructor create(e_,c_:Vec3);virtual;
      function GetEmit(x:Vec3):Vec3;virtual;
      function GetColor(x:Vec3):Vec3;virtual;
   end;

   RingTextureClass = class(TextureClass)
      p,ColorDiff:Vec3;
      constructor create(e_,c_,p_,cd_:Vec3);virtual;
      function GetColor(x:Vec3):Vec3;override;
   end;

   SphereBitmapTextureClass = class(TextureClass)
      p:Vec3;
      BMP:BMPRecord;
      constructor create(e_,c_,p_:Vec3;FNPath,FN:string);virtual;
      function GetColor(x:Vec3):Vec3;override;
   end;
   ScaleBitmapTextureClass = class(SphereBitmapTextureClass)
      scale:real;//bitmapを変倍
      xwh,zwh,xwl,zwl:real;
      constructor create(e_,c_,p_:Vec3;scale_:real;FNPath,FN:string);virtual;
      function GetColor(x:Vec3):Vec3;override;
   end;   
   ShapeClass = class;
   
   HitInfo = record
      isHit:boolean;
      t:real;
      id:integer;//本来オブジェクトにしたいが・・・
      obj:ShapeClass;
   end;

   InterInfo = record
      t:real;
      id:integer;
   end;
         
   AABBRecord = record
      little,large:Vec3;
      function hit(r:RayRecord;tmin,tmax:real):boolean;
      function new(m0,m1:Vec3):AABBRecord;
      function MargeBoundBox(box1:AABBRecord):AABBRecord;
   end;

   ShapeClass = class
      tx:TextureClass;
      m:MaterialClass;
      BoundBox:AABBRecord;
      constructor Create(e_,c_:Vec3;refl_:RefType);virtual;
      procedure SetAttrib(e_,c_:Vec3;refl_:RefType);virtual;
      function intersect(const r:RayRecord):InterInfo;virtual;abstract;
      function GetNorm(x:Vec3):Vec3;virtual;abstract;
      procedure DumpM;
      procedure Dump;virtual;abstract;
   end;
   
   SphereClass = class(ShapeClass)
      p:Vec3;
      rad:real;       //radius
      constructor Create(rad_:real;p_,e_,c_:Vec3;refl_:RefType);virtual;
      function intersect(const r:RayRecord):InterInfo;override;
      function GetNorm(x:Vec3):Vec3;override;
      procedure Dump;override;
   end;

   function StrToRefl(st:string):RefType;


implementation

function AABBRecord.MargeBoundBox(box1:AABBRecord):AABBRecord;
var
   small,big:Vec3;
begin
   small:=vec3.new(min(little.x, box1.little.x),
                      min(little.y, box1.little.y),
                      min(little.z, box1.little.z));

   big:=vec3.new(max(large.x, box1.large.x),
                     max(large.y, box1.large.y),
                     max(large.z, box1.large.z) );

   result.new(small,big);
end;


function AABBRecord.new(m0,m1:Vec3):AABBRecord;
begin
   little:=m0;large:=m1;
   result:=self;
end;

function AABBRecord.hit(r:RayRecord;tmin,tmax:real):boolean;
var
   invD,t0,t1,tswap:real;
begin
   //tminがマイナスの場合を除外するため、tmin=EPS,tmax=INFとしている。引数意味なくない？
   invD := 1.0 / r.d.x;
   t0 := (little.x - r.o.x) * invD;
   t1 := (large.x - r.o.x) * invD;
   if (invD < 0.0) then begin tswap:=t1;t1:=t0;t0:=tswap end;

   if t0>tmin then tmin:=t0;
   if t1<tmax then tmax:=t1;
   if (tmax <= tmin) then exit(false);

   invD := 1.0 / r.d.y;
   t0 := (little.y - r.o.y) * invD;
   t1 := (large.y - r.o.y) * invD;
   if (invD < 0.0) then begin tswap:=t1;t1:=t0;t0:=tswap end;

   if t0>tmin then tmin:=t0;
   if t1<tmax then tmax:=t1;
   if (tmax <= tmin) then exit(false);

   invD := 1.0 / r.d.z;
   t0 := (little.z - r.o.z) * invD;
   t1 := (large.z - r.o.z) * invD;
   if (invD < 0.0) then begin tswap:=t1;t1:=t0;t0:=tswap end;

   if t0>tmin then tmin:=t0;
   if t1<tmax then tmax:=t1;
   if (tmax <= tmin) then exit(false);

   result:=true;
end;

procedure ShapeClass.SetAttrib(e_,c_:Vec3;refl_:RefType);
begin
   tx:=TextureClass.Create(e_,c_);
   if refl_=DIFF then m:=DiffuseClass.Create;
   if refl_=SPEC then m:=MirrorClass.Create;
   if refl_=REFR then m:=RefractClass.Create;
end;

constructor ShapeClass.Create(e_,c_:Vec3;refl_:RefType);
begin
   SetAttrib(e_,c_,refl_);
end;


constructor SphereClass.Create(rad_:real;p_,e_,c_:Vec3;refl_:RefType);
begin
   p:=p_;
   inherited create(e_,c_,refl_);
   rad:=rad_;
   BoundBox.new(p - vec3.new(rad, rad, rad),
                p + vec3.new(rad, rad, rad));
end;
function SphereClass.intersect(const r:RayRecord):InterInfo;
var
  op:Vec3;
  t,b,det:real;
begin
   op:=p-r.o;
   t:=eps;b:=op*r.d;det:=b*b-op*op+rad*rad;
   if det<0 then 
      result.t:=INF
   else begin
      det:=sqrt(det);
      t:=b-det;
      if t>eps then 
         result.t:=t
      else begin
         t:=b+det;
         if t>eps then 
            result.t:=t
         else
            result.t:=INF;
      end;
   end;
end;

function SphereClass.GetNorm(x:Vec3):Vec3;
begin
  result:=(x-p).norm;
end;

procedure ShapeClass.DumpM;
begin
  write('ref=',m.IDStr,' e=');WriteVec(tx.e);write(' c=');WriteVec(tx.c);
end;
procedure SphereClass.Dump;
begin
   write('radius=',rad,' p=');WriteVec(p);
   writeln;
end;
function MaterialClass.IDStr:string;
begin
   result:='';
end;

function DiffuseClass.GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;
var
   r1,r2,r2s:real;
   u,v,w,d:Vec3;
begin
   r1:=2*PI*random;r2:=random;r2s:=sqrt(r2);
   w:=nl;
   if abs(w.x)>0.1 then
      u:=(vec3.new(0,1,0)/w).norm 
   else begin
      u:=(vec3.new(1,0,0)/w ).norm;
   end;
   v:=w/u;
   d := (u*cos(r1)*r2s + v*sin(r1)*r2s + w*sqrt(1-r2)).norm;
   result.r:=RayRecord.new(x,d);
   result.cpc:=1.0;
end;

function DiffuseClass.IDStr:string;
begin
   result:='DIFF';
end;

function MirrorClass.GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;
begin
   result.r:=RayRecord.new(x,r.d-nl*2*(nl*r.d) );//オリジナルはnlではなくnなので不安があるが
   result.cpc:=1.0;
end;

function MirrorClass.IDStr:string;
begin
   result:='SPEC';
end;

function RefractClass.GetRay(r:RayRecord;x,n,nl:Vec3):TraceInfo;
var
   RefRay:RayRecord;
   into:boolean;
   nc,nt,nnt,ddn,cos2t,q,a,b,c,R0,Re,RP,Tr,TP:real;
   tDir:Vec3;
   p:real;
begin
   RefRay:=RayRecord.new(x,r.d-n*2*(n*r.d) );
   into:= (n*nl>0);
   nc:=1;nt:=1.5;
   if into then nnt:=nc/nt else nnt:=nt/nc; ddn:=r.d*nl; 
   cos2t:=1-nnt*nnt*(1-ddn*ddn);
   if cos2t<0 then begin   // Total internal reflection
      result.r:=RefRay;
      result.cpc:=1.0;
      exit;
   end;
   if into then q:=1 else q:=-1;
   tdir := (r.d*nnt - n*(q*(ddn*nnt+sqrt(cos2t)))).norm;
   if into then Q:=-ddn else Q:=tdir*n;
   a:=nt-nc; b:=nt+nc; R0:=a*a/(b*b); c := 1-Q;
   Re:=R0+(1-R0)*c*c*c*c*c;Tr:=1-Re;P:=0.25+0.5*Re;RP:=Re/P;TP:=Tr/(1-P);

   if random<p then begin// 反射
      result.r:=RefRay;
      result.cpc:=RP;
   end
   else begin //屈折
      result.r:=RayRecord.new(x,tdir);
      result.cpc:=TP;
   end;
end;

function RefractClass.IDStr:string;
begin
   result:='REFR';
end;


constructor TextureClass.create(e_,c_:Vec3);
begin
   e:=e_;c:=c_;
end;

function TextureClass.GetEmit(x:Vec3):Vec3;
begin
   result:=e;
end;

function TextureClass.GetColor(x:Vec3):Vec3;
begin
   result:=c;
end;

function StrToRefl(st:string):RefType;
begin
   case st of
      'DIFF':result:=DIFF;
      'SPEC':result:=SPEC;
      'REFR':result:=REFR;
   else result:=DIFF
   end;
end;

constructor RingTextureClass.create(e_,c_,p_,cd_:Vec3);
begin
   p:=p_;
   ColorDiff:=cd_;
   inherited create(e_,c_);
end;


function RingTextureClass.GetColor(x:Vec3):Vec3;
begin
   result:=c;
   if ((p-x).len mod 100) >50 then begin
      result:=result+ColorDiff;
   end ;
end;

constructor SphereBitmapTextureClass.create(e_,c_,p_:Vec3;FNPath,FN:string);
var
   FPFN:string;
begin
   p:=p_;
      if FNPath <> '' then
      FPFN := IncludeTrailingPathDelimiter(FNPath) + FN
   else
      FPFN := FN;

   if not FileExists(FPFN) then Exit;

   BMP.readFile(FPFN);
   inherited create(e_,c_);
end;   

function SphereBitmapTextureClass.GetColor(x:Vec3):Vec3;
var
   uv:Vec2;
begin
   uv:=uv.DirToUV(x-self.p);
   result:=RGBtoColor(BMP.GetPixel(trunc(BMP.bmpWidth*uv.u),trunc(BMP.bmpHeight*uv.v)));
end;

constructor ScaleBitmapTextureClass.create(e_,c_,p_:Vec3;scale_:real;FNPath,FN:string);
begin
   inherited create(e_,c_,p_,FNPath,FN);
   scale:=scale_;
   xwh:=BMP.bmpWidth / (scale*2);
   zwh:=BMP.bmpHeight /(scale*2);
   xwl:=-BMP.bmpWidth / (scale*2);
   zwl:=-BMP.bmpHeight /(scale*2);
end;

function ScaleBitmapTextureClass.GetColor(x:Vec3):Vec3;
var
   xz:Vec3;
   x1,z1:real;
begin
   xz:=x-p;
   x1:=xz.x;
   z1:=xz.z;
   if (x1>xwh) or (z1>zwh) or(x1<xwl) or (z1<zwl) then
      result:=c
   else
      result:=RGBtoColor(BMP.GetPixel(trunc((x1+xwh)*scale),trunc((zwh-z1)*scale)) );
end;

begin
  
end.
