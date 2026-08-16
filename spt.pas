program sppthread;    
{$mode objfpc}
{$modeswitch advancedrecords}
{$codepage utf8} // ← これを追加！

uses
   {$ifdef unix}
   cthreads,cmem,
   cwstring, // ← Linux/Unix環境でUTF-8(System/WideString)を正しく扱うために必須
   {$endif}
   SysUtils,Classes,Math,getopts,
   uVect,uBMP,uShape,uRadiance,uScene,uObjShape,uTOMLcfg;

const
   MaxThread=32;
var
   BMP:BMPrecord;
   sc:SceneRecord;

type

   //スタックサイズが不定を嫌ってdynamic arrayは使わない
   LineArray=array[0..255*255] of rgbColor;

   TMyThread = class(TThread)
      wide,height,samps:integer;//render option
      y,yInc:integer;
      Line:LineArray;
      cam:CamRecord;
      procedure Execute; override;
      procedure AddAxis;
   end;


procedure TMyThread.Execute;
var
   x,sx,sy,s:integer;
   r,tColor:Vec3;
begin
   while y<height do begin
      if y mod 10 =0 then writeln('y=',y);
      for x:= 0 to wide - 1 do begin
         tColor:=ZeroVec;
         for sy := 0 to 1 do begin
            for sx := 0 to 1 do begin
               r:=ZeroVec;
               for s := 0 to sc.cam.samps - 1 do begin
                  r:= r+sc.Radiance(sc.cam.GetRay(x,y,sx,sy), 0)/ sc.cam.samps;
               end;(*samps*)
               tColor:=tColor+ ClampVector(r)* 0.25;
            end;(*sx*)
         end;(*sy*)
         Line[x]:=ColToRGB(tColor);
      end;(* for x *)
      Synchronize(@AddAxis);
   end;(*for y*)
end;

procedure TMyThread.AddAxis;
var
   j:integer;
   yAxis:integer;
begin
   yAxis:=height-y-1;
   for j:=0 to wide-1 do BMP.SetPixel(j,yAxis,line[j]);
   y:=y+yInc;
end;
  
  
var
   i: integer;
   w,h,samps: integer;
   modelnum,threadnum:integer;
   AspectFlag:boolean;//trueの場合16:9
   ArgInt:integer;
   FN,ArgFN,tomlFN:string;
   c:char;
   StarTime:TDateTime;
   SPTDoc:SPTOMLDocument;
var
   ThreadAry:array[0..MaxThread-1] of TMyThread;
begin
   tomlFN:='./toml/original-scene.toml';
   ThreadNum:=8;
   modelnum:=0;
   FN:='out.png';
   w:=640 ;h:=480;
   //w:=1920;h:=1080;
   samps := 16;
   AspectFlag:=false;
   c:=#0;
   repeat
      c:=getopt('adm:o:s:t:w:T:O:h?');
      case c of
         'a':begin
                AspectFlag:=true;
             end;
         'd':begin
                PolygonDumpFlag:=true;
             end;
         'm' : begin
                  ArgInt:=StrToInt(OptArg);
                  modelnum:=ArgInt;
                  writeln ('model number=',ModelNum);
               end;
         'T' : begin
                  ArgFN:=OptArg;
                  if ArgFN<>'' then begin tomlFN:=ArgFN;
                     writeln ('TOML FileName =',tomlFN);
                     modelnum:=100;
                  end;   
               end;
         'O' : begin
                  ArgFN:=OptArg;
                  if ArgFN<>'' then begin ObjFilePath:=ArgFN;
                     writeln ('ObjFilePath =',tomlFN);
                   end;   
               end;                  
          'o' : begin
                  ArgFN:=OptArg;
                  if ArgFN<>'' then FN:=ArgFN;
                  writeln ('Output FileName =',FN);
               end;
         's' : begin
                  ArgInt:=StrToInt(OptArg);
                  samps:=ArgInt;
                  writeln('samples =',ArgInt);
               end;
         't' : begin
                  ArgInt:=StrToInt(OptArg);
                  ThreadNum:=ArgInt;
                  if ThreadNum>=MaxThread then Threadnum:=MaxThread;
                  writeln('Thread Number =',ThreadNum);
               end;
         'w' : begin
                  ArgInt:=StrToInt(OptArg);
                  w:=ArgInt;h:=w *3 div 4;
                  writeln('w=',w,' ,h=',h);
               end;
         'h','?',':' : begin
                      writeln(' -a aspect 16:9 on');
                      writeln(' -d dump flag on');
                      writeln(' -m [0..7,10,11,20,30] scene number');
                      writeln(' -o [finename] output filename');
                      writeln(' -s [samps] sampling count');
                      writeln(' -t [thread num]');
                      writeln(' -w [width] screen width pixel');
                      writeln(' -T [toml Filename]');
                      writeln(' -O [obj file path]');
                     halt;
                   end;
      end; { case }
   until c=endofoptions;

   if AspectFlag then begin
      h:=w*9 div 16;
   end;
   BMP.new(w,h);
   sc.new(w,h,samps);

   Randomize;
   writeln ('read Data! The time is : ',TimeToStr(Time));
   case modelnum of
      100:begin
          writeln('TOML filename=',tomlFN);   
          SPTDoc:=SPTOMLDocument.Create(tomlFN);   
          sc.cam:=SPTDoc.camNew;
          sc.scList.add(SPTDoc.GetShapeList);
          SPTDoc.AddBVHList(sc);
          BMP.new(sc.cam.w,sc.cam.h);//TOMLファイル優先のため
       end;
      70: CornelBunnyScene(sc);
      60: SkyBunnyScene(sc);
      50: bunnyScene(sc);
      40: TeapotScene(sc);
      30: InitObjScene(sc);
      20: bvhRandomScene(sc);
      11: EvenlySpiralScene(sc);
      10: SpiralScene(sc);
      6:  IslandScene(sc);
      5:  RandomScene(sc);
      4:  WadaScene(sc);
      3:  ForestScene(sc);
      2:  SkyScene(sc);
      1:  InitNEScene(sc);
   else
      InitScene(sc);
   end;(*case*)
   writeln ('load Data! The time is : ',TimeToStr(Time));
   writeln('samps=',sc.cam.samps);
   writeln('size=',sc.cam.w,'x',sc.cam.h);
   writeln('model=',modelnum);
   writeln('threads=',threadnum);
   writeln('output=',FN);
   writeln('Obj File Path=',ObjFilePath);

   StarTime:=Time; 

   for i:=0 to ThreadNum-1 do begin
      ThreadAry[i]:=TMyThread.Create(true);
      ThreadAry[i].FreeOnTerminate:=false;
      //falseにしないとスレッドが休止時の後始末ができない。
      ThreadAry[i].y:=i;
      ThreadAry[i].wide:=sc.cam.w;
      ThreadAry[i].height:=sc.cam.h;
      ThreadAry[i].cam:=sc.cam;
      ThreadAry[i].samps:=sc.cam.samps;
      ThreadAry[i].yInc:=ThreadNum;
   end;
   writeln('Setup!');
   
   for i:=0 to ThreadNum-1 do begin
      ThreadAry[i].Start;
   end;
   //このルーチンが別途で無いとマルチスレッドにならない
   for i:=0 to ThreadNum-1 do begin
      ThreadAry[i].WaitFor;
   end;
   writeln('The time is : ',TimeToStr(Time));
   writeln('Calcurate time is=',TimeToStr(Time-StarTime));
   BMP.WriteFile(FN);
end.
  
