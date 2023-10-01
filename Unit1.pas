unit Unit1;

interface

uses
{$IFDEF MSWINDOWS}
  WinApi.Windows, Vcl.Graphics,
{$ENDIF}System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.Controls.Presentation, FMX.StdCtrls, FMX.Objects, FMX.Utils,
  System.ImageList, FMX.ImgList, FMX.ListBox, FMX.Filter.Effects, FMX.Edit,
  FMX.Colors, FMX.Memo.Types, FMX.ScrollBox, FMX.Memo;

type
  TForm1 = class(TForm)
    ImageMain: TImage;
    Button1: TButton;
    Button2: TButton;
    OpenDialog: TOpenDialog;
    ImageList: TImageList;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Button2Click(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private

  public
    procedure LoadImage;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}


uses TensorFlowLiteFMX;

var
  Matting: TTensorFlowLiteFMX;

const
  MattingInputSize = 512;
  MattingOutputSize = 512;

type
  PInputImage = ^TInputImage;
  TInputImage = array [0 .. 3 - 1] of array [0 .. MattingInputSize - 1] of array [0 .. MattingInputSize - 1] of Float32;

  PInputTrimap = ^TInputTrimap;
  TInputTrimap = array [0 .. 1 - 1] of array [0 .. MattingInputSize - 1] of array [0 .. MattingInputSize - 1] of Float32;

type
  POutputDataMatting = ^TOutputDataMatting;
  TOutputDataMatting = array [0 .. MattingOutputSize * MattingOutputSize - 1] of Float32;

procedure TForm1.LoadImage;
var
  FScale: Single;
  FLeft, FTop, FWidth, FHeight: Single;
begin
{$IFDEF MSWINDOWS}
  if ImageMain.MultiResBitmap.Count > 0 then
    ImageMain.MultiResBitmap[0].Free;

  ImageMain.MultiResBitmap.Add;

  if ImageList.Source[0].MultiResBitmap.Count > 0 then
    ImageList.Source[0].MultiResBitmap[0].Free;

  ImageList.Source[0].MultiResBitmap.Add;
  ImageList.Source[0].MultiResBitmap[0].Bitmap.LoadFromFile('troll.png');

  if ImageList.Source[1].MultiResBitmap.Count > 0 then
    ImageList.Source[1].MultiResBitmap[0].Free;

  ImageList.Source[1].MultiResBitmap.Add;
  ImageList.Source[1].MultiResBitmap[0].Bitmap.LoadFromFile('troll_trimap.png');

  ImageMain.Bitmap.Assign(ImageList.Source[1].MultiResBitmap[0].Bitmap);

{$ENDIF MSWINDOWS}
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  LoadImage;
end;

var
  mean: array of Float32 = [0.485, 0.456, 0.406];
  sdt: array of Float32 = [0.229, 0.224, 0.225];

procedure TForm1.Button2Click(Sender: TObject);
var
  i, X, Y, FPixel: DWORD;
  FColorsImage, FColorsTrimap: PAlphaColorArray;
  FBitmap: TBitmap;
  FBitmapDataImage, FBitmapDataTrimap: TBitmapData;
  FInputImage: PInputImage;
  FInputTrimap: PInputTrimap;
  FOutputData: POutputDataMatting;
  FStatus: TFLiteStatus;
  FColor: TAlphaColorRec;

begin
  LoadImage;

  ImageList.Source[0].MultiResBitmap[0].Bitmap.Map(TMapAccess.Read, FBitmapDataImage);
  ImageList.Source[1].MultiResBitmap[0].Bitmap.Map(TMapAccess.Read, FBitmapDataTrimap);

  GetMem(FInputImage, Matting.Input.Tensors[1].DataSize);
  try
    for Y := 0 to MattingInputSize - 1 do
    begin
      FColorsImage := PAlphaColorArray(FBitmapDataImage.GetScanline(Y));

      for X := 0 to MattingInputSize - 1 do
      begin
        FInputImage[0][Y][X] := (((TAlphaColorRec(FColorsImage[X]).R * 0.0078125) - 1) * mean[0]) / sdt[0];
        FInputImage[1][Y][X] := (((TAlphaColorRec(FColorsImage[X]).G * 0.0078125) - 1) * mean[1]) / sdt[1];
        FInputImage[2][Y][X] := (((TAlphaColorRec(FColorsImage[X]).B * 0.0078125) - 1) * mean[2]) / sdt[2];
      end;
    end;

    FStatus := Matting.SetInputData(1, FInputImage, Matting.Input.Tensors[1].DataSize);
  finally
    FreeMem(FInputImage);
  end;

  GetMem(FInputTrimap, Matting.Input.Tensors[0].DataSize);
  try
    for Y := 0 to MattingInputSize - 1 do
    begin
      FColorsTrimap := PAlphaColorArray(FBitmapDataTrimap.GetScanline(Y));

      for X := 0 to MattingInputSize - 1 do
      begin
        FInputTrimap[0][Y][X] := 1;

        if (TAlphaColorRec(FColorsTrimap[X]).R = 0) then
          FInputTrimap[0][Y][X] := 0
        else if TAlphaColorRec(FColorsTrimap[X]).R = 255 then
          FInputTrimap[0][Y][X] := 2
      end;
    end;

    FStatus := Matting.SetInputData(0, FInputTrimap, Matting.Input.Tensors[0].DataSize);
  finally
    FreeMem(FInputTrimap);
  end;

  if FStatus <> TFLiteOk then
  begin
    ShowMessage('SetInputData Error');
    Exit;
  end;

  FStatus := Matting.Inference;

  if FStatus <> TFLiteOk then
  begin
    ShowMessage('Inference Error');
    Exit;
  end;

  GetMem(FOutputData, Matting.Output.Tensors[0].DataSize);
  try
    FStatus := Matting.GetOutputData(0, FOutputData, Matting.Output.Tensors[0].DataSize);

    if FStatus <> TFLiteOk then
      Exit;

    FBitmap := TBitmap.Create;
    try
      FBitmap.Width := MattingOutputSize;
      FBitmap.Height := MattingOutputSize;

      FBitmap.Canvas.BeginScene;
      try
        FBitmap.Canvas.Clear(TAlphaColorRec.Black);

        FPixel := 0;

        for Y := 0 to MattingOutputSize - 1 do
        begin
          FColorsTrimap := PAlphaColorArray(FBitmapDataTrimap.GetScanline(Y));
          FColorsImage := PAlphaColorArray(FBitmapDataImage.GetScanline(Y));

          for X := 0 to MattingOutputSize - 1 do
          begin
            if (FOutputData[FPixel] >= 0) and (FOutputData[FPixel] <= 1) then
            begin
              if TAlphaColorRec(FColorsTrimap[X]).R = 0 then
              begin
                FBitmap.Canvas.Stroke.Color := TAlphaColorRec.Black;
                FBitmap.Canvas.DrawEllipse(RectF(X, Y, (X + 1), (Y + 1)), 1);
              end
              else if TAlphaColorRec(FColorsTrimap[X]).R = 255 then
              begin
                FBitmap.Canvas.Stroke.Color := TAlphaColorRec.White;
                FBitmap.Canvas.DrawEllipse(RectF(X, Y, (X + 1), (Y + 1)), 1);
              end
              else
              begin
                FColor.R := Round(255 * FOutputData[FPixel]);
                FColor.G := Round(255 * FOutputData[FPixel]);
                FColor.B := Round(255 * FOutputData[FPixel]);
                FColor.A := 255;

                FBitmap.Canvas.Stroke.Color := FColor.Color;
                FBitmap.Canvas.DrawEllipse(RectF(X, Y, (X + 1), (Y + 1)), 1);
              end;
            end;

            Inc(FPixel);
          end;
        end;

      finally
        FBitmap.Canvas.EndScene;
      end;

      ImageMain.Bitmap.Assign(FBitmap);
      ImageMain.InvalidateRect(ImageMain.ClipRect);
    finally
      FBitmap.Free;
    end;
  finally
    FreeMem(FOutputData);
  end;

  ImageList.Source[0].MultiResBitmap[0].Bitmap.Unmap(FBitmapDataImage);
  ImageList.Source[1].MultiResBitmap[0].Bitmap.Unmap(FBitmapDataTrimap);

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
{$IFDEF MSWINDOWS}
  SetPriorityClass(GetCurrentProcess, HIGH_PRIORITY_CLASS);
  Matting := TTensorFlowLiteFMX.Create(Self);
  Matting.LoadModel('matting.tflite', 12);
{$ENDIF}
end;

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Matting.Destroy;
end;

end.
