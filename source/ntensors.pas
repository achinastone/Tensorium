﻿unit ntensors;

{$ifdef fpc}
  {$mode delphi}
  {$ModeSwitch typehelpers}
  {$ModeSwitch nestedprocvars}
  {$ModeSwitch advancedrecords}
  {$ifdef CPUX86_64}
     {$asmmode intel}
     //{$FPUType AVX2}
  {$endif}
  {$ifdef MSWINDOWS}{$FPUType AVX2}
  {$endif}
{$else}
{$endif}
{$excessprecision off}
{$pointermath on}
{$WRITEABLECONST ON}
{$define USE_FMA}
{$M+}

interface

uses Classes, SysUtils, TypInfo, Generics.Defaults, syncobjs, Math
  {$if defined(FRAMEWORK_FMX)}// Delphi FMX
  , UITypes, FMX.Graphics
  {$elseif defined(FPC)}
  , FPImage
  , FPImgCanv
  , FPCanvas
  , FPReadPNG
  , FPWritePNG
  , FPReadBMP
  , FPWriteBMP
  , FPReadJPEG
  , FPWriteJPEG
  , termesc
  {$elseif defined(FRAMEWORK_VCL)}  // LCLC or VCL
  , Graphics
  {$endif}

  {$ifdef USE_MULTITHREADING}
  , steroids
  {$endif}
  {$if defined(USE_MKL)}
  , mkl_vml
  , mkl_cblas
  {$endif}
  {$if defined(USE_OPENBLAS)}
  , openblas
  {$endif}
  {$ifdef USE_OPENCL}
  //, OpenCL
  , nnOpenCL
    {$ifdef CL_BLAST}
    , clblast
    {$endif}
  {$endif}

  {$if defined(MSWINDoWS)}
  , shellapi
  {$endif}
  {$ifdef USE_TELEMETRY}
  , nOpMetrics
  {$endif}
  ;

const
  {$ifdef fpc}
  {$ifopt D+}
  isDEBUG = true;
  {$endif}
  maxSingleExp = ln(MaxSingle);
  minSingleExp = ln(MinSingle);
  maxDoubleExp = ln(MaxDouble);
  minDoubleExp = ln(minDouble);
  {$else}
  maxSingleExp = 88.722839;
  minSingleExp = -87.33654475;
  maxDoubleExp = 708;
  minDoubleExp = -708;

  {$endif}
  sEPSILON = 0.000001;
  dEPSILON = 0.000000001;
  //sEPSILON     = MinSingle;
  //dEPSILON     = minDouble;


  PI = 3.1415926535897932384626433;
  TAU = 3.1415926535897932384626433 * 2;
  LOG2E = 1.4426950408889634;
  SQRTPIx2 = 2.5066282746310005024157652515873;//sqrt(PIx2);

  {$if not declared(CBLAS_LAYOUT)}
type
  CBLAS_Layout = (CblasRowMajor = 101, CblasColMajor = 102);
  {$else}
  const
    CblasRowMajor = CBLAS_Layout.CblasRowMajor;
    CblasColMajor = CBLAS_Layout.CblasColMajor;
  {$endif}
  {$if not declared(CBLAS_ORDER)}
type
  CBLAS_ORDER = CBLAS_Layout;
  {$endif}
  {$if not declared(CBLAS_TRANSPOSE)}
type
  CBLAS_TRANSPOSE = (CblasNoTrans = 111, CblasTrans = 112, CblasConjTrans =
    113, CblasConjNoTrans = 114);
  {$else}
  const
    CblasNoTrans = CBLAS_TRANSPOSE.CblasNoTrans;
    CblasTrans = CBLAS_TRANSPOSE.CblasTrans;
    CblasConjTrans = CBLAS_TRANSPOSE.CblasConjTrans;
    CblasConjNoTrans = CBLAS_TRANSPOSE.CblasConjNoTrans ;
  {$endif}

  {$if not declared(PInt32)}
  type PInt32 = PInteger;
  {$endif}

type
  PPSingle = ^PSingle;
  PSizeInt = ^SizeInt;
  SizeInt = nativeint;
  SizeUInt = nativeuint;
  TSizes = TArray<SizeInt>;
  TBitPixels = TArray<TArray<longword>>;
  TMapFunc<T> = function(const a: T; const index: SizeInt): T;
  {$ifdef FPC}
  TMapFuncLambda<T> = function(const a:T; const index:SizeInt):T is Nested;
  {$else}
  DWORD = longword;
  PDWORD = ^DWORD;
  QWORD = uint64;
  PQWORD = ^QWORD;
  PIntPtr = ^IntPtr;
  TMapFuncLambda<T> = reference to function(const a: T; const index: SizeInt): T;
  {$endif}

  TMapProc<T, PT> = function(const a: T; const index: SizeInt;
    const AShape: TArray<SizeInt>;
    const src: PT): T;
  TReduceProc<T, PT> = function(const a, b: T; const index: SizeInt;
    const src: PT; const N: SizeInt): T;
  {$ifdef FPC}
  TMapProcLambda<T, PT> = function(const a:T; const index:SizeInt;  const AShape:TArray<SizeInt>;const src: PT):T is Nested;
  TReduceProcLambda<T, PT>  = function(const a, b:T;  const index:SizeInt; const src: PT; const N:SizeInt):T is nested;
  {$else}
  TMapProcLambda<T, PT> = reference to function(const a: T; const index: SizeInt;
    const N: TArray<SizeInt>; const src: PT): T;
  TReduceProcLambda<T, PT> = reference to function(const a, b: T;
    const index: SizeInt; const src: PT; const N: SizeInt): T;
  {$endif}

  TTensorPrintStyle = (psValues, psGray5, psGray24, psGray, psColor8, psColor24);
  TComputingDevice = (cdCPU, cdOpenCL, cdCUDA, cdCUDNN);

const
  psColor = psColor24;

type
  {$ifndef FPC}
  {$ifndef USE_MULTITHREADING}
  TThreadProcNested = reference to procedure(idx: IntPtr; ptr: pointer);
  {$endif}
  {$endif}

  { TTensor }
  TTensor<T> = record
  const
    elementSize = SizeOf(T);
  type
    PT = ^T;
    TUnaryFunc = function(const b: T): T;
    TUnaryPFunc = function(const b: T; const index: SizeInt; const P: PT): T;
    TBinaryFunc = function(const a, b: T): T;
    TBinaryOp = procedure(var dst: T; const src: T);
    TCastIOp = function(const v: SizeInt): T;
    TTernaryOp = procedure(var dst: T; const src1, src2: T);

    TUnaryVecFunc = function(const N: SizeInt; const src: PT; const stride: SizeInt): T;
    TUnaryVecFunc1 = function(const N: SizeInt; const a: T; const src: PT;
      const stride: SizeInt): T;
    TBinaryVecFunc = function(const N: SizeInt; const src1: PT;
      const stride1: SizeInt; const src2: PT; const stride2: SizeInt): T;

    TFMAvssOp = procedure(const N: SizeInt; const dst: PT;
      const stride: SizeInt; const scale, bias: T);

    TUnaryVecOp = procedure(const N: SizeInt; const src: PT;
      const src1Stride: SizeInt; const dst: PT; const src2Stride: SizeInt);
    TUnaryVecOp1 = procedure(const N: SizeInt; const ALPHA: T;
      const src: PT; const src1Stride: SizeInt);
    TUnaryVecOp2 = procedure(const N: SizeInt; const ALPHA: T;
      const src: PT; const src1Stride: SizeInt; const dst: PT; const src2Stride: SizeInt);

    TBinaryVecOp = procedure(const N: SizeInt; const src1: PT;
      const src1Stride: SizeInt; const src2: PT; const src2Stride: SizeInt;
      const dst: PT; const dstStride: SizeInt);

  private
  class var
    workspace: TArray<T>;
    {$ifdef USE_OPENCL}
    devWorkspace : TCLMemory;
    {$endif}
    defaultDevice : TComputingDevice;
    Plus, Minus, Times, Division: TBinaryFunc;
    sqr, sqrt, exp, log, __abs: TUnaryFunc;
    CastI: TCastIOp;
    checkNan : function(const v:T):boolean;
    checkInf : function(const v:T):boolean;

    fmavvv: TBinaryVecOp;
    fmavss: TFMAvssOp;
    varv, rssv, sumSqrDiffv, sumAbsDiffv: TUnaryVecFunc1;
    sumsqrdiffvv, sumAbsDiffvv: TBinaryVecFunc;
    normvv, normblkvv: TBinaryVecOp;

    sqrtv, expv, logv, andvv, orvv, xorvv, notv, log10v, log2v,
    absv, absDiffv, sinv, cosv, tanv, cotanv, tanHv, arcsinv,
    arcCosv, arcTanv, ArcSinHv, arcCosHv, arcTanHv: TUnaryVecOp;

    addblkvv, subblkvv, mulblkvv, divblkvv : procedure(const N: SizeInt; const src: PT;
      const src1Stride: SizeInt; const dst: PT; const dstStride: SizeInt; const batch : SizeInt = 1);
    mulAddBlkvv : procedure (const N: SizeInt; const A: PT; const aStride: SizeInt; const B: PT; const bStride: SizeInt; const dst: PT; const dstStride: SizeInt; const batch:Sizeint = 1);

    argMaxv, argMinv, argmaxabsv, argminabsv: function(const N: SizeInt;
      const src: PT; const INCX: SizeInt): SizeInt;
    argMaxv32, argMinv32, argmaxabsv32, argminabsv32: function(
      const N: SizeInt; const src: PT; const INCX: int32): int32;
    dotvv: function(N: SizeInt; src1: PT; stride1: SizeInt; src2: PT;
      stride2: SizeInt): T;
    minmaxvsi: procedure(const N: SizeInt; const src: PT; const stride: SizeInt;
      var outMin, outMax: T; var outArgMin, outArgMax: SizeInt);
    minmaxvss: procedure(const N: SizeInt; const src: PT; const stride: SizeInt;
      var outMin, outMax: T);
    vcvtb: procedure(const N: SizeInt; const src: PT; const dst: pbyte);
    //vcvtl   : procedure(const N:SizeInt; const src:PT; const dst:PUint32);
    //vcvtq   : procedure(const N:SizeInt; const src:PT; const dst:PUint64);
    vcvti8: procedure(const N: SizeInt; const src: PT; const dst: PShortInt);
    vcvti16: procedure(const N: SizeInt; const src: PT; const dst: PSmallInt);
    vcvti32: procedure(const N: SizeInt; const src: PT; const dst: PInt32);
    //vcvti64 : procedure(const N:SizeInt; const src:PT; const dst:PInt64 );
    vcvtd: procedure(const N: SizeInt; const src: PT; const dst: PDouble);
    vcvts: procedure(const N: SizeInt; const src: PT; const dst: PSingle);

    threshv, absThreshv: function(const N: SizeInt; var src: PT;
      const stride: SizeInt; const thresh: T; const ifAbove, ifEqualOrBelow: PT): SizeInt;

    matDet: function(const mat: PT; const rank: SizeInt): T;
    matDeg: procedure(const matIn: PT; const matOut: PT; const rank: SizeInt;
      const row, col: SizeInt);
    matCof: procedure(const matIn: PT; const matOut: PT; const rank: SizeInt);
    matInv: procedure(const matIn: PT; const matOut: PT; const rank: SizeInt);
    matTra: procedure(const matIn: PT; const matOut: PT; const rows, cols: SizeInt);

    toStr: function(const v: T): string;
    Compare: function(const a, b: T): SizeInt;
    rand: function(const a: T): T;
    randG: function(const aMean, aStdDev: T): T;
  public
  class var
    Zero, One: T;
    addvv, subvv, mulvv, divvv, minvv, maxvv: TBinaryVecOp;

    addvs, subvs, divvs: TUnaryVecOp2;
    mulvs, andvs, orvs, xorvs, shrvs, shlvs, minvs, maxvs: TUnaryVecOp1;
    sqrv: TUnaryVecOp;
    powv, lognv: TUnaryVecOp2;
    sumv, asumv, sumsqrv, maxv, minv, minabsv, maxabsv: TUnaryVecFunc;
    gemm: procedure(const Order: CBLAS_LAYOUT; const TransA, TransB: CBLAS_TRANSPOSE;
      const M, N, K: SizeInt; const ALPHA: T; const A: PT; const lda: SizeInt;
      const B: PT; const ldb: SizeInt; const BETA: T; const C: PT; const ldc: SizeInt);
    axpysvv: TUnaryVecOp2;
    normvss: procedure(const N: SizeInt; const src: PT;
      const aMean, aStdDev: T);
    MeansAndVarsDelta: procedure(const delta, x, mean, variance: TTensor<T>;
      const mean_delta, variance_delta: TTensor<T>; const offset:SizeInt =0);
    normalizeDelta: procedure(
      const x, mean, variance, mean_delta, variance_delta: TTensor<T>;
      const Delta: TTensor<T>; const offset : SizeInt =0);
    im2Colvv: procedure(const aChannels, aHeight, aWidth: Sizeint;
      const kernelHeight, kernelWidth,
      padHeight, padWidth, strideY, strideX, dilationY, dilationX: SizeInt;
      const inData: PT; const inOffset: SizeInt;
      const outData: PT; const outOffset: SizeInt; const batch: SizeInt = 1;
      const multiThread: boolean = False);
    col2imvv: procedure(const aChannels, aHeight, aWidth: Sizeint;
      const kernelHeight, kernelWidth,
      padHeight, padWidth, strideY, strideX, dilationY, dilationX: SizeInt;
      const inData: PT; const inOffset: SizeInt;
      const outData: PT; const outOffset: SizeInt; const batch: SizeInt = 1;
      const multiThread: boolean = False);
  public
    Data: PT;
    DynData: TArray<T>;
    {$if defined(USE_OPENCL)}
    devData: TCLMemory;
    {$elseif defined(USE_CUDA)}
    {$endif}
    Groups, Steps: SizeInt;
    computingDevice: TComputingDevice;
  private
    FShape: TSizes;
    FDimSizes: TSizes;
    FStrides: TSizes;
    lastOP: TComputingDevice;
  private
    function GetDimensions: SizeInt;
    function GetGroup(idx: SizeInt): TTensor<T>; overload;
    function GetValue(idx: TSizes): T;
    procedure SetGroup(idx: SizeInt; AValue: TTensor<T>);
    procedure SetShape(AValue: TSizes);
    procedure SetStrides(AValue: TSizes);
    procedure SetValue(idx: TSizes; AValue: T);

    // revert to simple math
    class function __plus(const a, b: T): T; static;
    class function __minus(const a, b: T): T; static;
    class function __times(const a, b: T): T; static;
    class function __division(const a, b: T): T; static;
    class function __casti(const v: SizeInt): T; static;

    class function sPlus(const a, b: single): single; static;
    class function sminus(const a, b: single): single; static;
    class function sMul(const a, b: single): single; static;
    class function sDiv(const a, b: single): single; static;
    class function sCasti(const v: SizeInt): single; static;

    class function dPlus(const a, b: double): double; static;
    class function dminus(const a, b: double): double; static;
    class function dMul(const a, b: double): double; static;
    class function dDiv(const a, b: double): double; static;
    class function dCasti(const v: SizeInt): double; static;

    class function ubPlus(const a, b: byte): byte; static;
    class function ubminus(const a, b: byte): byte; static;
    class function ubMul(const a, b: byte): byte; static;
    class function ubDiv(const a, b: byte): byte; static;
    class function ubCasti(const v: SizeInt): byte; static;

    class function sbPlus(const a, b: shortint): shortint; static;
    class function sbMinus(const a, b: shortint): shortint; static;
    class function sbMul(const a, b: shortint): shortint; static;
    class function sbDiv(const a, b: shortint): shortint; static;
    class function sbCasti(const v: SizeInt): shortint; static;

    class function swPlus(const a, b: smallint): smallint; static;
    class function swMinus(const a, b: smallint): smallint; static;
    class function swMul(const a, b: smallint): smallint; static;
    class function swDiv(const a, b: smallint): smallint; static;
    class function swCasti(const v: SizeInt): smallint; static;

    class function slPlus(const a, b: longint): longint; static;
    class function slMinus(const a, b: longint): longint; static;
    class function slMul(const a, b: longint): longint; static;
    class function slDiv(const a, b: longint): longint; static;
    class function slCasti(const v: SizeInt): longint; static;

    class function sqPlus(const a, b: int64): int64; static;
    class function sqMinus(const a, b: int64): int64; static;
    class function sqMul(const a, b: int64): int64; static;
    class function sqDiv(const a, b: int64): int64; static;
    class function sqCasti(const v: SizeInt): int64; static;

    class procedure cvtsb(const N: SizeInt; const src: PSingle; const dst: pbyte); static;
    class procedure cvtsi8(const N: SizeInt; const src: PSingle;
      const dst: PShortInt); static;
    class procedure cvtsi16(const N: SizeInt; const src: PSingle;
      const dst: PSmallInt); static;
    class procedure cvtsi32(const N: SizeInt; const src: PSingle;
      const dst: PInt32); static;
    class procedure cvtsd(const N: SizeInt; const src: PSingle;
      const dst: PDouble); static;
    class procedure cvtss(const N: SizeInt; const src: PSingle;
      const dst: PSingle); static;

    class procedure cvtdd(const N: SizeInt; const src: PDouble;
      const dst: PDouble); static;
    class procedure cvtdb(const N: SizeInt; const src: PDouble; const dst: pbyte); static;
    class procedure cvtdi8(const N: SizeInt; const src: PDouble;
      const dst: PShortInt); static;
    class procedure cvtdi16(const N: SizeInt; const src: PDouble;
      const dst: PSmallInt); static;
    class procedure cvtdi32(const N: SizeInt; const src: PDouble;
      const dst: PInt32); static;
    class procedure cvtds(const N: SizeInt; const src: PDouble;
      const dst: PSingle); static;

    class procedure cvtbi8(const N: SizeInt; const src: pbyte; const dst: PInt32); static;
    class procedure cvtbi16(const N: SizeInt; const src: pbyte;
      const dst: PShortInt); static;
    class procedure cvtbi32(const N: SizeInt; const src: pbyte;
      const dst: PSmallInt); static;
    class procedure cvtbs(const N: SizeInt; const src: pbyte; const dst: PSingle);
      static;
    class procedure cvtbd(const N: SizeInt; const src: pbyte; const dst: PDouble);
      static;

    class procedure cvti8s(const N: SizeInt; const src: PInt32; const dst: PSingle); static;
    class procedure cvti8d(const N: SizeInt; const src: PInt32; const dst: PDouble); static;

    class procedure cvti16s(const N: SizeInt; const src: PInt32;
      const dst: PSingle); static;
    class procedure cvti16d(const N: SizeInt; const src: PInt32;
      const dst: PDouble); static;

    class procedure cvti32s(const N: SizeInt; const src: PInt32;
      const dst: PSingle); static;
    class procedure cvti32d(const N: SizeInt; const src: PInt32;
      const dst: PDouble); static;

    class procedure cvti64s(const N: SizeInt; const src: PInt32;
      const dst: PSingle); static;
    class procedure cvti64d(const N: SizeInt; const src: PInt32;
      const dst: PDouble); static;

    class function sToStr(const v: single): string; static;
    class function dToStr(const v: double): string; static;
    class function i8ToStr(const v: shortint): string; static;
    class function i16ToStr(const v: smallint): string; static;
    class function i32ToStr(const v: int32): string; static;
    class function i64ToStr(const v: int64): string; static;
    class function bToStr(const v: byte): string; static;

    class function _str(const v: T): string; static;
    class function _compare(const a, b: T): SizeInt; static;
    class function subPrint(const src: TTensor<T>; const Indecies: TSizes;
      const lvl: SizeInt): string; static;
    class procedure Permute(var dst: TTensor<T>; const src: TTensor<T>;
      const newShape, Indecies, newIndecies, newArrange: TSizes; const lvl: SizeInt);
      overload; static;
    class function Sum(const N: SizeInt; const src: PT; const stride: SizeInt = 1): T;
      overload; static;
    class procedure Sums(const N: SizeInt; const src: PT; const groups: SizeInt;
      const dst: PT; const func: TUnaryPFunc; const Data: PT = nil); overload; static;
    class function Dot(N: SizeInt; src1: PT; stride1: SizeInt;
      src2: PT; stride2: SizeInt = 1): T; overload; static;
    class function sumSqrDiff(const N: SizeInt; const src1: PT; const stride1: SizeInt; const src2: PT; const stride2: SizeInt = 1): T; overload; static;
    class function sumSqrDiff(const N: SizeInt; const src1: T; const src2: PT; const stride2: SizeInt = 1): T; overload; static;
    class function sumAbsDiff(const N: SizeInt; const src1: PT; const stride1: SizeInt; const src2: PT; const stride2: SizeInt = 1): T; overload; static;
    class function sumAbsDiff(const N: SizeInt; const src1: T; const src2: PT; const stride2: SizeInt = 1): T; overload; static;
    class function Variance(const N: SizeInt; const mean: T; const src: PT;
      const stride: SizeInt = 1): T; overload; static;
    class function sumSqr(const n: SizeInt; const src: PT;
      const stride: SizeInt = 1): T; static;
    class function sumAbs(const n: SizeInt; const src: PT;
      const stride: SizeInt = 1): T; overload; static;

    // Residual Sum of Squares
    class function RSS(const N: SizeInt; const mean: T; const src: PT;
      const stride: SizeInt = 1): T; overload; static;
    class procedure axpy(const N: SizeInt; const a: T; const X: PT;
      const INCX: SizeInt; const Y: PT; const INCY: SizeInt); overload; static;

    class function __max(const N: SizeInt; const src: PT; const stride: SizeInt): T;
      overload; static;
    class function __min(const N: SizeInt; const src: PT; const stride: SizeInt): T;
      overload; static;

    class procedure __max(const N: SizeInt; const src1: PT; const stride1: SizeInt;
      const src2: PT; const stride2: SizeInt; const dst: PT; const dstStride: SizeInt);
      overload; static;
    class procedure __min(const N: SizeInt; const src1: PT; const stride1: SizeInt;
      const src2: PT; const stride2: SizeInt; const dst: PT; const dstStride: SizeInt);
      overload; static;

    class procedure __max(const N: SizeInt; const a: T; const src1: PT;
      const stride1: SizeInt); overload; static;
    class procedure __min(const N: SizeInt; const a: T; const src1: PT;
      const stride1: SizeInt); overload; static;

    class procedure __maxs(const N: SizeInt; const src: PT; const groups: SizeInt;
      const dst: PT); overload; static;
    class procedure __mins(const N: SizeInt; const src: PT; const groups: SizeInt;
      const dst: PT); overload; static;

    class procedure minMax(const N: SizeInt; const src: PT; const stride: SizeInt;
      var outMin, outMax: T; var outArgMin, outArgMax: SizeInt); overload; static;
    class procedure minMax(const N: SizeInt; const src: PT; const stride: SizeInt;
      var outMin, outMax: T); overload; static;

    class function argMin(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): SizeInt; overload; static;
    class function argMax(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): SizeInt; overload; static;

    class function minAbs(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): T; overload; static;
    class function maxAbs(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): T; overload; static;

    class function argMinAbs(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): SizeInt; overload; static;
    class function argMaxAbs(const N: SizeInt; const src: PT;
      const stride: SizeInt = 1): SizeInt; overload; static;

    class function argMin(const N: SizeInt; const src: PT; const stride: int32 = 1): int32;
      overload; static;
    class function argMax(const N: SizeInt; const src: PT; const stride: int32 = 1): int32;
      overload; static;
    class function argAbsMin(const N: SizeInt; const src: PT;
      const stride: int32 = 1): int32;
      overload; static;
    class function argAbsMax(const N: SizeInt; const src: PT;
      const stride: int32 = 1): int32;
      overload; static;

    class function threshold(const N: SizeInt; var src: PT; const stride: SizeInt;
      const thresh: T; const ifAbove: PT = nil; const ifEqualOrBelow: PT = nil): SizeInt;
      overload; static;
    class function absThreshold(const N: SizeInt; var src: PT;
      const stride: SizeInt; const thresh: T; const ifAbove: PT = nil;
      const ifEqualOrBelow: PT = nil): SizeInt; overload; static;
    class procedure _conv2d(const src: PT; ker: PT; var dest: PT;
      const wSrc, hSrc, wKernel, hKernel, wPad, hPad, xStr, yStr, xDil, yDil: SizeInt); static;
    class procedure polynomial(const N: SizeInt; const coef: TArray<T>;
      dst: PT; const aStdDev: T); overload; static;
    class function xLinear(const n, deg: SizeInt; const x: T; const coef: TArray<T>): T; static;
    class function deCompose(var qr: PT; const m, n, rwidthq: SizeInt; var alpha: PT; var pivot: PSizeInt): integer; static;
    class procedure solve(const qr: TArray<T>; const M, N, rwidthq: SizeInt; var alpha: TArray<T>; var pivot: TArray<SizeInt>; var r, y: TArray<T>); static;


    procedure AssignTo(var dst: TTensor<T>);
    //class function matDeterminant(const mat:PT; const rank:SizeInt):T; overload;static;
    //class procedure matDegrade(const matIn:PT; const matOut:PT;const rank:SizeInt; const row,col:SizeInt); overload; static;
    //class procedure matCofactors(const matIn:PT; const matOut:PT; const rank:SizeInt);overload; static;
    //class procedure matInverse(const matIn:PT; const matOut:PT; const rank:SizeInt);overload; static;
    //class procedure matTranspose(const matIn:PT; const matOut:PT; const rows, cols:SizeInt);overload; static;
  public
    function w(): SizeInt; inline;
    function h(): SizeInt; inline;
    function c(): SizeInt; inline;
    function n(): SizeInt; inline;

    property Dimensions: SizeInt read GetDimensions;
    property Shape: TSizes read FShape write SetShape;
    property Strides: TSizes read FStrides write SetStrides;
    property Value[idx: TSizes]: T read GetValue write SetValue;
    constructor Create(const newShape: TSizes; aGroups: SizeInt = 0; ASteps: SizeInt = 0); overload;
    procedure Free();
    function wasGPU(): boolean; inline;
    {$if defined(USE_OPENCL)}
    procedure setOCL;
    {$endif}
    {$if defined(USE_OPENCL)}
    procedure setCPU;
    {$endif}
    procedure pushToDevice;
    procedure pullFromDevice; overload;
    procedure pullFromDevice(var dst :TTensor<T>); overload;
    procedure resetReference;
    //procedure convertTo<C>(var Trnsor:TTensor<C>);
    procedure Fill(const val: T; const interval: T; const stride: SizeInt = 1;
      start: SizeInt = 0; Count: SizeInt = -1); overload;
    procedure Fill(const val: T); overload;
    procedure FillExt(const val: T; const offset: SizeInt; const N: SizeInt); overload;
    procedure Sort(dst:TTensor<T>; const Descending : boolean = false);overload;
    procedure Sort(const Descending : boolean = false);overload;
    procedure linSpace(const start: T; const Finish: T; const N: SizeInt = 0);
    procedure UniformDistribution(const minVal, maxVal: T);
    procedure NormalDistribution(const aMean, aStdDev: T);
    function sample(const n : SizeInt):SizeInt;
    function findNaNs:TArray<SizeInt>;
    function findInfinities:TArray<SizeInt>;
    procedure setAll(const val: T; const stride: SizeInt = 1);
    procedure reShape(const newShape: TSizes; const batch: SizeInt = 0; const aSteps:SizeInt =0);
    function reSize(const newShape: TSizes; const batch: SizeInt = 0; const aSteps:SizeInt =0): TTensor<T>;
    function Equal(const tensor: TTensor<T>): boolean;
    procedure replace(const what, aReplace: T);
    procedure find(const what: T; var indecies: TArray<SizeInt>);
    function indexOf(const val: T): SizeInt;
    function Permute(const newArrange: TSizes; dstTensor: Pointer = nil): TTensor<T>; overload;
    procedure CopyTo(const dst: TTensor<T>; const dstOffset :SizeInt =0; const dstStride: SizeInt = 1; const srcOffset : SizeInt = 0; const srcStride: SizeInt = 1; N: SizeInt = 0);
    procedure ShallowCopy(const Source: TTensor<T>); overload;
    procedure ShallowCopy(const Source: TArray<T>; const AShape:TArray<SizeInt> = nil); overload;
    function getIndex(const idx: TSizes): SizeInt; inline;
    function Size(): SizeInt; inline;
    function groupSize(): SizeInt; inline;
    function byteSize(): SizeInt; inline;
    function as2dWidth(): SizeInt; inline;
    function as2dHeight():sizeInt; inline;
    procedure Squeeze(dim: SizeInt = -1);
    procedure UnSqueeze(newDim: TSizes = nil);
    function toString(): string;
    procedure fromString(const src: string; const separator: string = ',');
    function loadFromFile(var F: file; blockSize: SizeInt = 0): SizeInt;
      overload;
    function loadFromFile(const FileName: string; blockSize: SizeInt = 0): SizeInt; overload;
    function SaveToFile(var F: file; blockSize: SizeInt = 0): SizeInt;
      overload;
    procedure SaveToImage(const FileName: string; Index: SizeInt = -1;
      const aNormalize: boolean = True); overload;

    // Tensor Pointer oprations
    procedure Add(const srcVector: PT; const dstOffset:SizeInt =0; N: SizeInt = -1; const dstStride: SizeInt = 1;
      const srcStride: SizeInt = 1); overload;
    procedure Subtract(const srcVector: PT; N: SizeInt = -1;
      const dstStride: SizeInt = 1; const srcStride: SizeInt = 1); overload;
    procedure Multiply(const srcVector: PT; N: SizeInt = -1;
      const dstStride: SizeInt = 1; const srcStride: SizeInt = 1); overload;
    procedure Divide(const srcVector: PT; N: SizeInt = -1; const dstStride: SizeInt = 1;
      const srcStride: SizeInt = 1); overload;

    procedure &or(const a: PT; const start: SizeInt = 0; N: SizeInt = 0); overload;
    procedure &and(const a: PT; const start: SizeInt = 0; N: SizeInt = 0); overload;
    procedure &xor(const a: PT; const start: SizeInt = 0; N: SizeInt = 0); overload;

    // Tensor Tensor Operation ( takes Groups into considration)
    procedure Add(const src: TTensor<T>; const offset :SizeInt =0; aSize:SizeInt =0); overload;
    procedure Subtract(const src: TTensor<T>); overload;
    procedure Multiply(const src: TTensor<T>; const offset :SizeInt =0; aSize:SizeInt =0); overload;
    procedure Divide(const src: TTensor<T>); overload;
    procedure fusedMultiplyAdd(const scale, bias: TTensor<T>); overload;
    procedure axpy(const a: T; const x: TTensor<T>); overload;
    function threshold(const AThreshold: T; const ifAbove: PT = nil;
      const ifElse: PT = nil; const stride: SizeInt = 1): SizeInt; overload;
    function absThreshold(const AThreshold: T; const ifAbove: PT = nil;
      const ifElse: PT = nil; const stride: SizeInt = 1): SizeInt; overload;

    procedure addSums(const src: TTensor<T>);
    procedure addDots(const src1, src2: TTensor<T>; const offset: SizeInt =0);
    procedure blockAdd(const src: TTensor<T>; const blockSize: SizeInt); overload;
    procedure blockSubtract(const src: TTensor<T>; const blockSize: SizeInt); overload;
    procedure blockMultiply(const src: TTensor<T>; const blockSize: SizeInt); overload;
    procedure blockDivide(const src: TTensor<T>; const blockSize: SizeInt); overload;

    // Tensor Scalar operation
    procedure Add(const src: T; N: SizeInt = -1; const dstStride: SizeInt = 1); overload;
    procedure Subtract(const src: T; N: SizeInt = -1; const dstStride: SizeInt = 1); overload;
    procedure Multiply(const src: T; N: SizeInt = -1; const dstStride: SizeInt = 1); overload;
    procedure Divide(const src: T; N: SizeInt = -1; const dstStride: SizeInt = 1); overload;
    procedure FusedMultiplyAdd(const scale, bias: T; const offset: SizeInt = 0;
      N: SizeInt = 0; const stride: SizeInt = 1); overload;

    procedure &shr(const a: T; const start: SizeInt = 0; N: SizeInt = 0);
    procedure &shl(const a: T; const start: SizeInt = 0; N: SizeInt = 0);

    procedure &or(const a: T; const start: SizeInt = 0; N: SizeInt = 0); overload;
    procedure &and(const a: T; const start: SizeInt = 0; N: SizeInt = 0); overload;
    procedure &xor(const a: T; const start: SizeInt = 0; N: SizeInt = 0); overload;
    procedure &not(const dst: PT; const start: SizeInt = 0; N: SizeInt = 0);


    procedure toBytes(const dst: pbyte; const start: SizeInt = 0; N: SizeInt = 0);
    procedure toInts(const dst: PInt32; const start: SizeInt = 0; N: SizeInt = 0);
    procedure toSingles(const dst: PSingle; const start: SizeInt = 0; N: SizeInt = 0);
    procedure toDoubles(const dst: PDouble; const start: SizeInt = 0; N: SizeInt = 0);

    procedure axpy(const a: T; const x: PT; N: SizeInt = -1; const offset: SizeInt = 0;
      dstStride: SizeInt = 1; xStride: SizeInt = 1); overload;
    function dot(const src: PT; N: SizeInt = -1; const Stride: SizeInt = 1;
      const srcStride: SizeInt = 1): T; overload;
    function sumSqrDiff(const src: PT; N: SizeInt = -1; const Stride: SizeInt = 1; const srcStride: SizeInt = 1): T; overload;
    function sumSqrDiff(const src: T; const Stride: SizeInt = 1): T; overload;
    function sumAbsDiff(const src: PT; N: SizeInt = -1; const Stride: SizeInt = 1; const srcStride: SizeInt = 1): T; overload;
    function sumAbsDiff(const src: T; const Stride: SizeInt = 1): T; overload;
    procedure matMul(const mat, dstMat: TTensor<T>; const transA: CBLAS_TRANSPOSE = CblasNoTrans; transB: CBLAS_TRANSPOSE = CblasNoTrans); overload;
    function matMul(const mat: TTensor<T>; const transA: CBLAS_TRANSPOSE = CblasNoTrans;
      transB: CBLAS_TRANSPOSE = CblasNoTrans): TTensor<T>; overload;
    function matDeterminant(): T; overload;
    procedure matDeterminant(var dst: PT); overload;
    procedure matInverse(const dst: TTensor<T>); overload;
    function matInverse(): TTensor<T>; overload;
    function matDegrade(const row, col: SizeInt): TTensor<T>; overload;
    procedure matTranspose(const dst: TTensor<T>); overload;
    function matTranspose(): TTensor<T>; overload;
    function SolveLeastSquares(const b: PT; var coef: PT): integer; overload;
    procedure Conv2D(const AKernels, dst: TTensor<T>; wPadding: SizeInt = -1;
      hPadding: SizeInt = -1; xStride: SizeInt = 1; yStride: SizeInt = 1;
      xDilation: SizeInt = 1; yDilation: SizeInt = 1); overload;
    procedure Abs(const stride: SizeInt = 1);
    procedure sumAbs(var dst: PT); overload;
    function sumAbs(const stride: SizeInt = 1): T; overload;
    procedure sumSquares(var dst: PT; const stride: SizeInt = 1); overload;
    function sumSquares(const stride: SizeInt = 1): T; overload;
    procedure absDiff(const x: TTensor<T>; const stride: SizeInt = 1);
    procedure square(const Stride: SizeInt = 1); overload;
    procedure square(var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    procedure squareRoot(const Stride: SizeInt = 1); overload;
    procedure squareRoot(var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    procedure ln(const stride: SizeInt = 1); overload;
    procedure ln(const a: T; var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    procedure Exponent(const stride: SizeInt = 1); overload;
    procedure Exponent(const a: T; var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    procedure power(const a: T; const stride: SizeInt); overload;
    procedure power(const a: T; var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    procedure logN(const a: T; const stride: SizeInt); overload;
    procedure logN(const a: T; var dst: PT; const srcStride: SizeInt = 1;
      const dstStride: SizeInt = 1); overload;
    function ResidualSumSquares(const Mean: T): T;
    procedure blockNormalize(const aMean, aStdDev: TTensor<T>; const blockSize: SizeInt);
    function Area(): SizeInt;
    function Volume(): SizeInt;

    function Sum(const stride: SizeInt = 1; N:SizeInt=0): T; overload;
    procedure Sums(const dst: PT; groups: SizeInt = 0;
      const activation: TUnaryPFunc = nil; const _data: PT = nil); overload;
    function mean(const stride: SizeInt = 1; N:SizeInt=0): T;
    function Variance(const stride: SizeInt = 1; N:SizeInt=0): T; overload;
    function stdDev(const stride: SizeInt = 1; N:SizeInt=0): T;
    procedure MeanAndVar(var aMean, aVar: T; const stride:SizeInt=1; N:SizeInt=0); overload;
    procedure Normalize(const aMean, aStdDev: T); overload;
    procedure Normalize(); overload;
    procedure Normalize(const aMean, aStdDev: TTensor<T>; const offset:SizeInt =0; aSize:SizeInt =0); overload;
    procedure maxNormalize(const aScale: T);

    procedure MeansAndVars(aMeans, aVars: TTensor<T>; const offset:SizeInt =0; aSize : SizeInt =0);

    function MSE(const vector: pointer; N: SizeInt): T;

    function min(const stride: SizeInt = 1): T; overload;
    function max(const stride: SizeInt = 1): T; overload;

    procedure min(const val: T); overload;
    procedure max(const val: T); overload;

    procedure min(const tensor: TTensor<T>); overload;
    procedure max(const tensor: TTensor<T>); overload;

    procedure mins(const dst: PT; groups: SizeInt = 0); overload;
    procedure maxs(const dst: PT; groups: SizeInt = 0); overload;

    procedure minMax(var outMin, outMax: T; var outArgMin, outArgMax: SizeInt;
      const stride: SizeInt = 1; N:SizeInt = 0); overload;

    procedure Clamp(const aMin, aMax: T; const dst: PT = nil);
    function argMin(const stride: SizeInt = 1): SizeInt; overload;
    function argMax(const stride: SizeInt = 1): SizeInt; overload;

    procedure argMin(const dst: PInt64); overload;
    procedure argMax(const dst: PInt64); overload;
    procedure argMinAbs(const dst: PInt64); overload;
    procedure argMaxAbs(const dst: PInt64); overload;

    procedure argMin(const dst: PInt32); overload;
    procedure argMax(const dst: PInt32); overload;
    procedure argMinAbs(const dst: PInt32); overload;
    procedure argMaxAbs(const dst: PInt32); overload;

    function minAbs(const stride: SizeInt = 1): T; overload;
    function maxAbs(const stride: SizeInt = 1): T; overload;

    procedure sin(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure cos(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure tan(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure cotan(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure tanH(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcSin(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcCos(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcTan(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcSinH(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcCosH(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure arcTanH(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure log10(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);
    procedure log2(const dst: PT; const stride: SizeInt = 1; const dstStride: SizeInt = 1);

    procedure addGaussianNoise(const aStdDev: T); overload;
    procedure addUniformNoise(const aErr: T); overload;

    function similarity(const src: PT): double;
    function cosineSimilarity(src: PT): T;
    procedure LerpValues(const _min, _max, _min2, _max2: T);
    function countNotValue(const src: T; const stride: SizeInt = 1): SizeInt; overload;
    function countValue(const src: T; const stride: SizeInt = 1): SizeInt;
    function findValues(const N:SizeInt; const values:PT):TArray<SizeInt>; overload;
    function findValues(const values:TArray<T>):TArray<SizeInt>; overload;
    procedure polynomial(const coef: TArray<T>); overload;
    procedure polynomial(const coef: TArray<T>; const aStdDev: T); overload;
    procedure histogram(const aCount: SizeInt; var dst: PInteger; outMin: PT = nil; outMax: PT = nil); overload;

    function Histogram(const aCount: SizeInt; outMin:PT = nil ; outMax:PT = nil): TArray<integer>; overload;

    function plot(const xAxis: TTensor<T>):TArray<SizeInt>; overload;
    function plot():TArray<SizeInt>; overload;

    function print(const consolePixel: TTensorPrintStyle = psValues; tile: SizeInt = 1; minVal: double = 0; maxVal: double = 0):TArray<SizeInt>; overload;
    function print(const scale: single; const gray: boolean = False; const tile: SizeInt = 1):TArray<SizeInt>; overload;
    function print(const scale: single; const idx: SizeInt):TArray<SizeInt>; overload;
    procedure printStat(N: SizeInt=0);
    function typeName(): string;

    procedure im2Col(const kernelWidth, kernelHeight, padWidth,
      padHeight, strideX, strideY, dilationX, dilationY: SizeInt; var dst: TTensor<T>;
      const AGroups: SizeInt = 1);
    procedure col2Im(const kernelWidth, kernelHeight, padWidth, padHeight, strideX, strideY, dilationX, dilationY: SizeInt; var src: TTensor<T>;
      const AGroups: SizeInt = 1);
    function map(const func: TMapFunc<T>): TTensor<T>; overload;
    function map(const func: TMapFuncLambda<T>): TTensor<T>; overload;
    procedure map(const func: TMapFunc<T>; var dst: TTensor<T>); overload;
    procedure map(const func: TMapFuncLambda<T>; var dst: TTensor<T>); overload;
    procedure map(const func: TMapProc<T, PT>); overload;
    procedure map(const func: TMapProcLambda<T, PT>); overload;

    function reduce(const func: TReduceProc<T, PT>): T; overload;
    function reduce(const func: TReduceProc<T, PT>; const start: T): T; overload;
    function reduce(const func: TReduceProcLambda<T, PT>): T; overload;
    function reduce(const func: TReduceProcLambda<T, PT>; const start: T): T; overload;

    procedure concat(const src: array of TTensor<T>);
    procedure addConcat(const src: array of TTensor<T>);

    procedure getGroup(const idx: SizeInt; const dst: PT); overload;
    property Group[idx: SizeInt]: TTensor<T> read GetGroup write SetGroup;
    class procedure histogram(const N: SizeInt; const src: PT; const aCount: SizeInt; dst: PInteger; outMin: PT = nil; outMax: PT = nil); overload; static;
    class function SolveLeastSquares(const a: PT; const M, N, rwidtha: SizeInt; const b: PT; var x: PT): integer; overload; static;
    class function FitPloynomial(const M: SizeInt; degree: SizeInt; const x, y: PT; var b: PT): integer; static;

    class function countMatch(const N: SizeInt; const src1: PT; const stride1: SizeInt; const src2: PT; const stride2: SizeInt): SizeInt; static;
    class function countNotValue(const N: SizeInt; const val: T; const src: PT; const stride: SizeInt = 1): SizeInt; overload; static;
    class function countValue(const N: SizeInt; const val: T; const src: PT; const stride: SizeInt = 1): SizeInt; overload; static;
    class procedure map(const func: TMapFunc<T>; const src: TTensor<T>; var dst: TTensor<T>); overload; static;
    class procedure map(const func: TMapFuncLambda<T>; const src: TTensor<T>; var dst: TTensor<T>); overload; static;
    class function reduce(const func: TReduceProc<T, PT>; const src: PT; const N, stride: SizeInt; const start: T): T; overload; static;
    class function reduce(const func: TReduceProcLambda<T, PT>; const src: PT; const N, stride: SizeInt; const start: T): T; overload; static;

    class function reduce(const func: TReduceProc<T, PT>; const src: PT; const N: SizeInt; const stride: SizeInt = 1): T; overload; static;
    class function reduce(const func: TReduceProcLambda<T, PT>; const src: PT; const N: SizeInt; const stride: SizeInt = 1): T; overload; static;

    class function product(const e: TSizes): SizeInt; overload; static;
    class function product(const N:SizeInt; const e: PSizeInt): SizeInt; overload; static;
    class operator Implicit(arr: TArray<T>): TTensor<T>;
    class operator Implicit(arr: TArray<TArray<T>>): TTensor<T>;
    class operator Implicit(arr: TArray<TArray<TArray<T>>>): TTensor<T>;
    class operator Implicit(arr: TArray<TArray<TArray<TArray<T>>>>): TTensor<T>;

    class operator Implicit(src: TTensor<T>): TArray<T>;
    class operator Implicit(src: TTensor<T>): PT;
    class operator Implicit(src: TTensor<T>): PSingle;
    class operator Implicit(src: TTensor<T>): PDouble;

    {$ifdef FPC}
    class operator Initialize(var dst:TTensor<T>);
    {$else}
    class operator Initialize(out dst: TTensor<T>);
    {$endif}

    class operator Finalize(var dst: TTensor<T>);
    {$ifdef MANAGED_MEM}
    {$ifdef FPC}
    class operator Copy(constref aSrc: TTensor<T>; var aDst: TTensor<T>);
    {$else}
    class operator Assign(var aDst: TTensor<T>; const [ref] aSrc: TTensor<T>);
    {$endif}
    {$endif}
    //class operator Implicit(arr: TArray< TArray<T> >): TTensor<T>;
    //class operator Implicit(src: TTensor<T>): TArray<TArray<T>>;
  end;


  PSingleTensor = ^TSingleTensor;
  PDoubleTensor = ^TDoubleTensor;
  PIntTensor = ^TIntTensor;
  PInt64Tensor = ^TInt64Tensor;
  PByteTensor = ^TByteTensor;
  PShortIntTensor = ^TShortIntTensor;

  TSingleTensor = TTensor<single>;
  TDoubleTensor = TTensor<double>;
  TIntTensor = TTensor<int32>;
  TInt64Tensor = TTensor<int64>;
  TByteTensor = TTensor<byte>;
  TShortIntTensor = TTensor<shortint>;
  TSizeIntTensor = TTensor<SizeInt>;

  { TensorUtils }

  TensorUtils = record
    class function lerp(const ratio, a, b: single): single; overload; static;
    class procedure swap(var a, b: single); overload; static;
    class function Gaussian(const u, sig, x: single): single; overload; static;
    class function Gaussian2d(const u, sig, x, y: single): single; overload; static;
    class function Phytha2d(const R, x, y: single): single; overload; static;
    class function lerp(const ratio, a, b: double): double; overload; static;
    class procedure swap(var a, b: double); overload; static;
    class function Gaussian(const u, sig, x: double): double; overload; static;
    class function Gaussian2d(const u, sig, x, y: double): double; overload; static;
    class function Phytha2d(const R, x, y: double): double; overload; static;
    class procedure get_embedding(const src: PSingle;
      const src_w, src_h, src_c, embedding_size, cur_w, cur_h, cur_n, cur_b: SizeInt;
      dst: PSingle); static;
    class procedure openPicture(const filename:string);static;
  end;

  { TTools }

  TTools<T> = record
  type PT = ^T;
    TComparefunc = function(const a, b: T): SizeInt;
    class procedure QuickSort(Arr: PT; L, R: SizeInt; const Compare: TComparefunc;
      const Descending: boolean = False); static;
  end;

//{$if defined(CPUX64)}
//procedure nn_fast(const A, B, C:PSingle; const ALPHA:single; const lda, ldb, ldc, i, CN, k:IntPtr);assembler;
//  {$endif}

procedure cblas_sgemm(const Order: CBLAS_LAYOUT; const TransA, TransB: CBLAS_TRANSPOSE;
  const M, N, K: SizeInt; const ALPHA: single; const A: PSingle;
  const lda: SizeInt; const B: PSingle; const ldb: SizeInt; const BETA: single;
  const C: PSingle; const ldc: SizeInt);

procedure cblas_dgemm(const Order: CBLAS_LAYOUT; const TransA, TransB: CBLAS_TRANSPOSE;
  const M, N, K: SizeInt; const ALPHA: double; const A: PDouble;
  const lda: SizeInt; const B: PDouble; const ldb: SizeInt; const BETA: double;
  const C: PDouble; const ldc: SizeInt);

{$if not declared(FillDWord)}
procedure FillDWord(var x; const count:SizeInt; const value:LongWord);
{$define FILLD_IMPL}
{$endif}

{$if not declared(FillQWord)}
procedure FillQWord(var x; const count:SizeInt; const value:UInt64);
{$define FILLQ_IMPL}
{$endif}

{$if not declared(FillWord)}
procedure FillWord(var x; const count:SizeInt; const value:Word);
{$define FILLW_IMPL}
{$endif}

function cblas_sdot(const N: SizeInt; const A: PSingle; const inca: SizeInt;
  const B: PSingle; const incb: SizeInt): single;
function ftos(f: double; prec: integer = 0): string;
procedure _line(const x0, y0, x1, y1: integer; const color: longword; const d: TBitPixels);

const

  {$ifdef CPUX64}
  InterlockedCompareExchange128Support : boolean = false;
  AESSupport                           : boolean = false;
  POPCNTSupport                        : boolean = false;
  SSE3Support                          : boolean = false;
  AVXSupport                           : boolean = false;
  AVX2Support                          : boolean = false;
  FMASupport                           : boolean = false;
  {$endif}

  sDigits: integer = 3;
  sSeparator: string = ',';

var
  rand_seed :uint32;
  _mutex: TCriticalSection;
  saxpy: procedure(const N: SizeInt; const a: single; const x, y: PSingle);
  sdot: function(const N: SizeInt; const x, y: PSingle): single;
  daxpy: procedure(const N: SizeInt; const a: double; const x, y: PDouble);
  ddot: function(const N: SizeInt; const x, y: PDouble): double;

  {$ifdef MSWINDOWS}
const
  kernel32 = 'kernel32.dll';
  STD_INPUT_HANDLE = DWORD(-10);
  STD_OUTPUT_HANDLE = DWORD(-11);
  STD_ERROR_HANDLE = DWORD(-12);

  INVALID_HANDLE_VALUE = THANDLE(-1);
  INVALID_FILE_SIZE = DWORD(-1);
  INVALID_SET_FILE_POINTER = DWORD(-1);
  INVALID_FILE_ATTRIBUTES = DWORD(-1);

  ENABLE_VIRTUAL_TERMINAL_PROCESSING = $0004;
  ENABLE_WRAP_AT_EOL_OUTPUT = $0002;
  ENABLE_PROCESSED_OUTPUT = 1;
  CONSOLE_TEXTMODE_BUFFER = 1;
  GENERIC_READ = $80000000;
  GENERIC_WRITE = $40000000;
  FILE_READ_DATA = $0001;
  FILE_WRITE_DATA = $0002;
  FILE_APPEND_DATA = $0004;

type
  PSECURITY_ATTRIBUTES = ^SECURITY_ATTRIBUTES;

  SECURITY_ATTRIBUTES = record
    nLength: DWORD;
    lpSecurityDescriptor: pointer;
    bInheritHandle: longbool;
  end;

function GetStdHandle(nStdHandle: DWORD): THandle; external kernel32;
function GetConsoleMode(hConsole: THandle; hMode: PLongWord): boolean;
  external kernel32;
function SetConsoleMode(hConsole: THandle; hMode: longword): boolean; external kernel32;
function CreateConsoleScreenBuffer(dwDesiredAccess, dwShareMode: longword;
  lpSecurityAttributes: PSECURITY_ATTRIBUTES; dwFlags: longword;
  lpScreenBufferData: pointer): THandle; external kernel32;
function SetConsoleActiveScreenBuffer(hConsoleOutput: THandle): boolean;
  external kernel32;
function CloseHandle(hObject: THandle): boolean; external kernel32;
function WriteConsole(hConsoleOutput: THandle; const lpBuffer: Pointer;
  nNumberOfCharsToWrite: longword; var lpNumberOfCharsWritten: longword;
  lpReserved: Pointer): boolean; external kernel32 Name 'WriteConsoleA';

  {$endif}
procedure srnd(const v:uint32);
function rnd():integer;

{$ifdef USE_OPENCL}

procedure initOpenCL(const platformId :SizeInt=0; const deviceId: SizeInt=0);

var
  ocl    : TNNOpenCL;
{$endif}

{$ifdef USE_TELEMETRY}
var
  benchmark : boolean;
{$endif}

implementation

{$ifdef FILLD_IMPL}
procedure FillDWord(var x; const count:SizeInt; const value:LongWord);
var i:SizeInt; p:PLongWord;
begin
  P := @x;
  for i:=0 to count-1 do
    p[i] := value
end;
{$endif}

{$ifdef FILLQ_IMPL}
procedure FillQWord(var x; const count:SizeInt; const value:UInt64);
var i:SizeInt; p:PUInt64;
begin
  P := @x;
  for i:=0 to count-1 do
    p[i] := value
end;
{$endif}

{$ifdef FILLW_IMPL}
procedure FillWord(var x; const count:SizeInt; const value:Word);
var i:SizeInt; p:PWord;
begin
  P := @x;
  for i:=0 to count-1 do
    p[i] := value
end;
{$endif}

{$if not declared(TMParams)}
type
  PMPParams = ^ TMPParams;
  TMPParams = record
     A,B,C,D,E,F,G,H,I,J,K,L,M,N,O,P,Q,R,S,T,U:Pointer;
  end;
{$endif}

{$if not declared(PPtrInt) }
type
  PPtrInt = ^IntPtr;
{$endif}

const
  WORKSPACE_SIZE = $1000;

  SIMD_REGS = 8;
  {$ifdef FPC}
  SIMD_SHFT  = BsfQWord(SIMD_REGS);
  {$else}
  {$if SIMD_REGS = 8}SIMD_SHFT = 3{$else} SIMD_SHFT = 2{$endif};
  {$endif}
  SIMD_OFF = SIMD_REGS * sizeof(single);

procedure saxpy_pas(const N: SizeInt; const a: single; const x, y: PSingle); inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[i] := a * x[i] + y[i];
end;

function sdot_pas(const N: SizeInt; const A, B: PSingle): single; inline;
var
  i: SizeInt;
begin
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + a[i] * b[i];
end;

procedure daxpy_pas(const N: SizeInt; const a: double; const x, y: PDouble); inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[i] := a * x[i] + y[i];
end;

function ddot_pas(const N: SizeInt; const A, B: PDouble): double; inline;
var
  i: SizeInt;
begin
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + a[i] * b[i];
end;

{$if defined(CPUX64)}
type
  PCPUID = ^TCPUID;
  TCPUID=packed record
     eax, ebx, ecx, edx :longword;
  end;

procedure  cpuid(const feature:longword; subleaf:longword; var res: TCPUID);assembler;
asm
  push rax
  push rbx
  push rcx
  push rdx
  mov r11            , res  // save result pos
  mov eax            , feature
  mov ecx            , subleaf
  cpuid
  mov [r11]          , eax
  mov [r11 + 4]      , ebx
  mov [r11 + 8]      , ecx
  mov [r11 + 12]     , edx
  pop rdx
  pop rcx
  pop rbx
  pop rax
end;

// copied from FPC cpu unit;
function XGETBV(const i : longword) : int64;assembler;
asm
{$ifndef win64}
    mov  rcx,  rdi
{$endif win64}
    // older FPCs don't know the xgetbv opcode
    db   $0f,  $01,  $d0
    and  eax,  $ffffffff
    shl  rdx,  32
    or   rax,  rdx
end;

procedure SetupSupport;
var
  cpu:TCPUID;
begin

  cpuid(1, 0, cpu);
  InterlockedCompareExchange128Support:=(cpu.ecx and $2000)<>0;
  AESSupport:=(cpu.ecx and $2000000)<>0;
  POPCNTSupport:=(cpu.ecx and $800000)<>0;

  AVXSupport:=
    { XGETBV suspport? }
    ((cpu.ecx and $08000000)<>0) and
    { xmm and ymm state enabled? }
    ((XGETBV(0) and 6)=6) and
    { avx supported? }
    ((cpu.ecx and $10000000)<>0);

  SSE3Support:=(cpu.ecx and $1)<>0;

  FMASupport:=AVXSupport and ((cpu.ecx and $1000)<>0);
  cpuid(7, 0, cpu);
  AVX2Support := AVXSupport and ((cpu.ebx and $20)<>0);
end;


const
  ymmd : array[0..7] of int32 = (0, 1, 2, 3, 4, 5, 6, 7);

function sdot_avx2(const N:SizeInt; const A,B:PSingle):single;assembler;{$ifdef FPC}nostackframe;{$endif}
asm
{$ifndef FPC}
  .NOFRAME
{$endif}
{$if SIMD_REGS = 4}
  vzeroupper
  mov              r11     ,    N
  vpxor            xmm0    ,    xmm0   ,   xmm0
  shr              r11     ,    SIMD_SHFT
  jz               @rem
@while:
  vmovups          xmm1    ,    oword [A]
  vfmadd231ps      xmm0    ,    xmm1   , oword [B]
  add              A       ,    SIMD_OFF
  add              B       ,    SIMD_OFF
  dec              r11
  jnz              @while

@rem:
  mov              r11     ,    N
  and              r11     ,    SIMD_REGS -1
  jz               @done
  vmovd            xmm3    ,    r11d
  vpxor            xmm1    ,    xmm1    , xmm1
  vpxor            xmm2    ,    xmm2    , xmm2
  vpbroadcastd     xmm3    ,    xmm3
  vpcmpgtd         xmm3    ,    xmm3    , [rip + ymmd]
  vmaskmovps       xmm1    ,    xmm3    , [A]
  vmaskmovps       xmm2    ,    xmm3    , [B]
  vfmadd231ps      xmm0    ,    xmm1    , xmm2

@done:
  //vextractf128     xmm1    ,    ymm0   ,   $1
  //vaddps           xmm0    ,    xmm0   ,   xmm1
  vhaddps          xmm0    ,    xmm0   ,   xmm0
  vhaddps          xmm0    ,    xmm0   ,   xmm0

{$elseif SIMD_REGS=8}

   mov              r11     ,    N
   vpxor            ymm0    ,    ymm0   ,   ymm0
   shr              r11     ,    SIMD_SHFT
   jz               @rem
@while:
   vmovups          ymm1    ,    yword [A]
   vfmadd231ps      ymm0    ,    ymm1   , yword [B]
   add              A       ,    SIMD_OFF
   add              B       ,    SIMD_OFF
   dec              r11
   jnz              @while

@rem:
   mov              r11     ,    N
   and              r11     ,    SIMD_REGS -1
   jz               @done
   vmovd            xmm3    ,    r11d
   vpxor            ymm1    ,    ymm1    , ymm1
   vpxor            ymm2    ,    ymm2    , ymm2
   vpbroadcastd     ymm3    ,    xmm3
   vpcmpgtd         ymm3    ,    ymm3    , [rip+ymmd]
   vmaskmovps       ymm1    ,    ymm3    , [A]
   vmaskmovps       ymm2    ,    ymm3    , [B]
   vfmadd231ps      ymm0    ,    ymm1    , ymm2

@done:
   vextractf128     xmm1    ,    ymm0   ,   $1
   vzeroupper
   vaddps           xmm0    ,    xmm0   ,   xmm1
   vhaddps          xmm0    ,    xmm0   ,   xmm0
   vhaddps          xmm0    ,    xmm0   ,   xmm0
{$endif}

end;

procedure saxpy_avx2(const N:SizeInt; const a:single; const x,y:PSingle);assembler;{$ifdef FPC}nostackframe;{$endif}
asm
  //push         r11
  //push         N
  {$ifndef FPC}
  .NOFRAME
  {$endif}
{$if SIMD_REGS = 4}
  vzeroupper
//  movss         xmm1   , a
  vbroadcastss xmm1   , a
  mov          r11    , N
  shr          r11    , (SIMD_SHFT + 2)    // div by 16 (4*4) = turns * SIMD_REGS
  jz           @rem1

@while:
  vmovups      xmm0   , oword [y]
  vmovups      xmm2   , oword [y+SIMD_OFF]
  vmovups      xmm3   , oword [y+SIMD_OFF*2]
  vmovups      xmm4   , oword [y+SIMD_OFF*3]

  vfmadd231ps  xmm0   , xmm1       , oword [x]           //xmm0
  vfmadd231ps  xmm2   , xmm1       , oword [x+SIMD_OFF]  //xmm2
  vfmadd231ps  xmm3   , xmm1       , oword [x+SIMD_OFF*2]//xmm8
  vfmadd231ps  xmm4   , xmm1       , oword [x+SIMD_OFF*3]//xmm3

  vmovups      oword [y]             , xmm0
  vmovups      oword [y+SIMD_OFF]    , xmm2
  vmovups      oword [y+SIMD_OFF*2]  , xmm3
  vmovups      oword [y+SIMD_OFF*3]  , xmm4

  add          x      , 4 * SIMD_OFF   // turns * offset
  add          y      , 4 * SIMD_OFF
  dec          r11
  jnz          @while

@rem1:
  mov          r11    , N
  and          r11    , (4*SIMD_REGS-1)       // mod 16  ( turns * SIMD_REGS)
  shr          r11    , SIMD_SHFT             // div SIMD_REGS
  jz           @rem

@while1:
  vmovups      xmm0   , [y]

  vfmadd231ps  xmm0   , xmm1       , [x]
  vmovups      [y]    , xmm0
  add          x      , SIMD_OFF
  add          y      , SIMD_OFF
  dec          r11
  jnz          @while1

@rem:
  mov          r11    , N
  and          r11    , (SIMD_REGS -1)       // mod SIMD_REGS
  jz           @done

@while2:
  vmovss       xmm0   , [y]
  vfmadd231ss  xmm0   , xmm1, [x]
  vmovss       [y]    , xmm0
  add          x      , 4
  add          y      , 4
  dec          r11
  jnz          @while2
{$elseif SIMD_REGS = 8}
//  movss         xmm2   , a
  vbroadcastss ymm1   , a
  mov          r11    , N
  shr          r11    , (SIMD_SHFT + 2)    // div by 16 (4*4) = turns * SIMD_REGS
  jz           @rem1

@while:
  vmovups      ymm0   , yword [y]
  vmovups      ymm2   , yword [y+SIMD_OFF]
  vmovups      ymm3   , yword [y+SIMD_OFF*2]
  vmovups      ymm4   , yword [y+SIMD_OFF*3]

  vfmadd231ps  ymm0   , ymm1       , yword [x]                 //xmm0
  vfmadd231ps  ymm2   , ymm1       , yword [x+SIMD_OFF]  //xmm2
  vfmadd231ps  ymm3   , ymm1       , yword [x+SIMD_OFF*2]//xmm8
  vfmadd231ps  ymm4   , ymm1       , yword [x+SIMD_OFF*3]//xmm3

  vmovups      yword [y]             , ymm0
  vmovups      yword [y+SIMD_OFF]    , ymm2
  vmovups      yword [y+SIMD_OFF*2]  , ymm3
  vmovups      yword [y+SIMD_OFF*3]  , ymm4

  add          x      , 4 * SIMD_OFF   // turns * offset
  add          y      , 4 * SIMD_OFF
  dec          r11
  jnz          @while

@rem1:
  mov          r11    , N
  and          r11    , (4*SIMD_REGS-1)       // mod 32  ( turns * SIMD_REGS)
  shr          r11    , SIMD_SHFT             // div SIMD_REGS
  jz           @rem

@while1:
  vmovups      ymm0   , [y]

  vfmadd231ps  ymm0   , ymm1       , [x]
  vmovups      [y]    , ymm0
  add          x      , SIMD_OFF
  add          y      , SIMD_OFF
  dec          r11
  jnz          @while1

@rem:
  mov          r11    , N
  and          r11    , (SIMD_REGS -1)       // mod SIMD_REGS
  jz           @done

@while2:
  vmovss       xmm0   , dword [y]
  vfmadd231ss  xmm0   , xmm1, [x]
  vmovss       dword [y]    , xmm0
  add          x      , 4
  add          y      , 4
  dec          r11
  jnz          @while2
{$endif}

@done:
  //pop          r11
  //vzeroupper
end;
{$endif}

{$if defined(CPUX64)}
procedure sscal(const N:SizeInt; const ALPHA:single; const A:Psingle);assembler;
asm
  mov          rax      ,    N
  vbroadcastss ymm0     ,    ALPHA
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vmulps       ymm1     ,    ymm0,  yword [A]
  vmovups      yword[A] ,    ymm1
  add          A        ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
@while2:
  vmulss       xmm1     ,    xmm0,  dword [A]
  vmovss       dword[A] ,    xmm1
  add          A        ,    4
  dec          rax
  jnz         @while2
@done:

end;

procedure sbias(const N:SizeInt; const ALPHA:single; const A:Psingle);assembler;
asm
  mov          rax      ,    N
  vbroadcastss ymm0     ,    ALPHA
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vaddps       ymm1     ,    ymm0,  yword [A]
  vmovups      yword[A] ,    ymm1
  add          A        ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
@while2:
  vaddss       xmm1     ,    xmm0,  dword [A]
  vmovss       dword[A] ,    xmm1
  add          A        ,    4
  dec          rax
  jnz         @while2
@done:

end;

function srss(const N:SizeInt; const AMean:single; const A:Psingle):single;assembler;
asm
  mov          rax      ,    N
  vbroadcastss ymm1     ,    AMean
  vxorps       ymm0     ,    ymm0,  ymm0
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vsubps       ymm2     ,    ymm1,  yword [A]
  vmulps       ymm2     ,    ymm2,  ymm2
  vaddps       ymm0     ,    ymm0,  ymm2
  add          A        ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
  vextractf128 xmm2     ,    ymm0,  1
  vzeroupper
  addps        xmm0     ,    xmm2
@while2:
  vsubss       xmm2     ,    xmm1,  dword [A]
  vmulss       xmm2     ,    xmm2,  xmm2
  vaddss       xmm0     ,    xmm0,  xmm2
  add          A        ,    4
  dec          rax
  jnz         @while2
@done:
  haddps       xmm0     ,    xmm0
  haddps       xmm0     ,    xmm0

end;

{$endif}

procedure cblas_sscal(const N: SizeInt; const ALPHA: single; const a: PSingle;
  const inca: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  {$if defined(CPUX64)}
  if AVX2Support and (inca=1) then
    sscal(N, ALPHA, A)
  else
  {$endif}
  for i := 0 to N - 1 do
    a[i * inca] := ALPHA * a[i * inca];

end;

procedure cblas_dscal(const N: SizeInt; const ALPHA: double; const a: PDouble;
  const inca: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    a[i * inca] := ALPHA * a[i * inca];

end;


const
  TILE_M = 4; // four operations                 (for A)
  TILE_N = 2 * 8;  // AVX2 ymm register size * 2 (for B)
  TILE_K = 16;  // loops
{$if defined(CPUX64)}

procedure mad(const dst:PSingle; const src1: single; const src2:PSingle);  vectorcall;inline;
begin
  dst[0] += src1 * src2[0];
  dst[1] += src1 * src2[1];
  dst[2] += src1 * src2[2];
  dst[3] += src1 * src2[3];
  dst[4] += src1 * src2[4];
  dst[5] += src1 * src2[5];
  dst[6] += src1 * src2[6];
  dst[7] += src1 * src2[7];
end;
//assembler; nostackframe;
//asm
//  vbroadcastss  ymm0, src1
//  vmovups       ymm1, yword [dst]
//  vfmadd231ps   ymm1, ymm0, yword [src2]
//  vmovups       yword [dst], ymm1
//end;



procedure nn_stable(const A, B, C:PSingle; const ALPHA:single; const lda, ldb, ldc, i, CN, k:IntPtr);
var j, kk : SizeInt;
  A1, A2, A3, A4 : single;
  C1, C2, C3, C4, C5, C6, C7, C8, B1, B2 : PSingle;
begin

  j := 0;
  while j< CN do begin

    C1 := C + i*ldc + j          ;
    C2 := C + i*ldc + j+8        ;

    C3 := C + (1+i)*ldc + j      ;
    C4 := C + (1+i)*ldc + j+8    ;

    C5 := C + (2+i)*ldc + j      ;
    C6 := C + (2+i)*ldc + j+8    ;

    C7 := C + (3+i)*ldc + j      ;
    C8 := C + (3+i)*ldc + j+8    ;

    for kk :=k to TILE_K + k-1  do begin
      A1 := A[(i+0)*lda + kk] * ALPHA ;
      A2 := A[(i+1)*lda + kk] * ALPHA ;
      A3 := A[(i+2)*lda + kk] * ALPHA ;
      A4 := A[(i+3)*lda + kk] * ALPHA ;
      B1 := B + (kk) * ldb + j        ;
      B2 := B + (kk) * ldb + j +8     ;

      mad(C1, A1, B1);
      mad(C2, A1, B2);
      mad(C3, A2, B1);
      mad(C4, A2, B2);
      mad(C5, A3, B1);
      mad(C6, A3, B2);
      mad(C7, A4, B1);
      mad(C8, A4, B2);
    end;
    inc(j, TILE_N)
  end
end;

procedure nn_fast(const A, B, C:PSingle; const ALPHA:single; const lda, ldb, ldc, i, CN, k:IntPtr);assembler;
asm
// save non-volatile registers to stack
  push               r12
  push               r13
  push               r14
  push               r15
{$ifdef MSWINDOWS}

  sub                  rsp      , 16*10                     // making stackspace to save xmm6-15
  vmovdqu              [rsp+$00], xmm6
  vmovdqu              [rsp+$10], xmm7
  vmovdqu              [rsp+$20], xmm8
  vmovdqu              [rsp+$30], xmm9
  vmovdqu              [rsp+$40], xmm10
  vmovdqu              [rsp+$50], xmm11
  vmovdqu              [rsp+$60], xmm12
  vmovdqu              [rsp+$70], xmm13
  vmovdqu              [rsp+$80], xmm14
  vmovdqu              [rsp+$90], xmm15
{$endif}

  xor                r10      , r10
  //mov                r10      , CN
@while_n:
  mov                r11      , i
  imul               r11      , ldc
  add                r11      , r10                       // (0+i)*ldc + j
  mov                r12      , r11
  add                r11      , ldc                       // (1+i)*ldc + j
  mov                r13      , r11
  add                r11      , ldc                       // (2+i)*ldc + j
  mov                r14      , r11
  add                r11      , ldc                       // (3+i)*ldc + j
  mov                r15      , r11

  vmovups            ymm8     , yword [C + 4 * r12]       // C[i*ldc + j]
  vmovups            ymm10    , yword [C + 4 * r12 + 32]  // C[i*ldc + j+8]

  vmovups            ymm9     , yword [C + 4 * r13]       // C[(1+i)*ldc + j]
  vmovups            ymm11    , yword [C + 4 * r13 + 32]  // C[(1+i)*ldc + j+8]

  vmovups            ymm12    , yword [C + 4 * r14]       // C[(2+i)*ldc + j]
  vmovups            ymm14    , yword [C + 4 * r14 + 32]  // C[(2+i)*ldc + j+8]

  vmovups            ymm13    , yword [C + 4 * r15]       // C[(3+i)*ldc + j]
  vmovups            ymm15    , yword [C + 4 * r15 + 32]  // C[(3+i)*ldc + j+8]

  xor                r11      , r11

@while:

  mov                rax      , i
  imul               rax      , lda                           //  i * lda
  add                rax      , k                             //  i * lda + k
  add                rax      , r11

{$if defined(UNIX) or defined(POSIX)}
  vmulss             xmm3     , ALPHA  ,  dword [A + 4 * rax] // A[i * lda + k] * ALPHA
  vbroadcastss       ymm3     , xmm3
{$else}
  vmulss             xmm0     , ALPHA  ,  dword [A + 4 * rax] // A[i * lda + k] * ALPHA
  vbroadcastss       ymm0     , xmm0
{$endif}
  add                rax      , lda                           //   (i+1)*lda + k
  vmulss             xmm1     , ALPHA  ,  dword [A + 4 * rax] // A[(i+1)*lda + k] * ALPHA
  vbroadcastss       ymm1     , xmm1

  add                rax      , lda                           //   (i+2)*lda + k
  vmulss             xmm2     , ALPHA  ,  dword [A + 4 * rax] // A[(i+2)*lda + k] * ALPHA
  vbroadcastss       ymm2     , xmm2

  add                rax      , lda                           //   (i+3)*lda + k
  vmulss             xmm4     , ALPHA  ,  dword [A + 4 * rax] // A[(i+3)*lda + k] * ALPHA
  vbroadcastss       ymm4     , xmm4


  mov                rax      , k
  add                rax      , r11
  imul               rax      , ldb                       // k * ldb
  add                rax      , r10                       // k * ldb + j
  //vmovups            ymm6     , yword [B + 4 * rax]       // B[k * ldb + j]
  //vmovups            ymm7     , yword [B + 4 * rax + 32]  // B[k * ldb + j+8]

{$ifdef USE_FMA}
{$if defined(UNIX) or defined(POSIX)}
  vfmadd231ps        ymm8     , ymm3    , yword [B + 4 * rax]

  vfmadd231ps        ymm10    , ymm3    , yword [B + 4 * rax + 32]
{$else}
  vfmadd231ps        ymm8     , ymm0    , yword [B + 4 * rax]

  vfmadd231ps        ymm10    , ymm0    , yword [B + 4 * rax + 32]
{$endif}

  vfmadd231ps        ymm9     , ymm1    , yword [B + 4 * rax]

  vfmadd231ps        ymm11    , ymm1    , yword [B + 4 * rax + 32]

  vfmadd231ps        ymm12    , ymm2    , yword [B + 4 * rax]

  vfmadd231ps        ymm14    , ymm2    , yword [B + 4 * rax + 32]


  vfmadd231ps        ymm13    , ymm4    , yword [B + 4 * rax]

  vfmadd231ps        ymm15    , ymm4    , yword [B + 4 * rax + 32]

{$else}
{$if defined(UNIX) or defined(POSIX)}

  vmulps             ymm5     , ymm3    , yword [B + 4 * rax]
  vaddps             ymm8     , ymm8    , ymm5

  vmulps             ymm5     , ymm3    , yword [B + 4 * rax + 32]
  vaddps             ymm10    , ymm10   , ymm5
{$else}
  vmulps             ymm5     , ymm0    , yword [B + 4 * rax]
  vaddps             ymm8     , ymm8    , ymm5

  vmulps             ymm5     , ymm0    , yword [B + 4 * rax + 32]
  vaddps             ymm10    , ymm10   , ymm5
{$endif}
  vmulps             ymm5     , ymm1    , yword [B + 4 * rax]
  vaddps             ymm9     , ymm9    , ymm5

  vmulps             ymm5     , ymm1    , yword [B + 4 * rax + 32]
  vaddps             ymm11    , ymm11   , ymm5

  vmulps             ymm5     , ymm2    , yword [B + 4 * rax]
  vaddps             ymm12    , ymm12   , ymm5

  vmulps             ymm5     , ymm2    , yword [B + 4 * rax + 32]
  vaddps             ymm14    , ymm14   , ymm5

  vmulps             ymm5     , ymm4    , yword [B + 4 * rax]
  vaddps             ymm13    , ymm13   , ymm5

  vmulps             ymm5     , ymm4    , yword [B + 4 * rax + 32]
  vaddps             ymm15    , ymm15   , ymm5
{$endif}

  inc                r11
  cmp                r11      , TILE_K
  jl                 @while

  vmovups            yword [C + 4 * r12]      , ymm8   // C[(0+i)*ldc + j]
  vmovups            yword [C + 4 * r12 + 32] , ymm10  // C[(0+i)*ldc + j+8]
  vmovups            yword [C + 4 * r13]      , ymm9   // C[(1+i)*ldc + j]
  vmovups            yword [C + 4 * r13 + 32] , ymm11  // C[(1+i)*ldc + j+8]
  vmovups            yword [C + 4 * r14]      , ymm12  // C[(2+i)*ldc + j]
  vmovups            yword [C + 4 * r14 + 32] , ymm14  // C[(2+i)*ldc + j+8]
  vmovups            yword [C + 4 * r15]      , ymm13  // C[(3+i)*ldc + j]
  vmovups            yword [C + 4 * r15 + 32] , ymm15  // C[(3+i)*ldc + j+8]

  add                r10    , TILE_N
  cmp                r10    , CN
  jl                 @while_n

//restore non-volatile registers
{$ifdef MSWINDOWS}
  vmovdqu            xmm6   , [rsp+$00]
  vmovdqu            xmm7   , [rsp+$10]
  vmovdqu            xmm8   , [rsp+$20]
  vmovdqu            xmm9   , [rsp+$30]
  vmovdqu            xmm10  , [rsp+$40]
  vmovdqu            xmm11  , [rsp+$50]
  vmovdqu            xmm12  , [rsp+$60]
  vmovdqu            xmm13  , [rsp+$70]
  vmovdqu            xmm14  , [rsp+$80]
  vmovdqu            xmm15  , [rsp+$90]
  add                rsp     , 16*10
{$endif}
  pop r15
  pop r14
  pop r13
  pop r12
end;

procedure nn_fastMP( idx:IntPtr; ptr:pointer);
var
  A_PART:Single;
  j
  , kk
  , i_d, k_d:IntPtr;
  p:PMPParams absolute ptr;
  A, B, C:PSingle;
  lda, ldb, ldc,
  CN
  ,CK, CM
  ,N
  ,K
   :IntPtr;
  ALPHA:single;
begin
  A     := p.A;
  B     := p.B;
  C     := p.C;
  lda   := PPtrInt(p.d)^;
  ldb   := PPtrInt(p.e)^;
  ldc   := PPtrInt(p.f)^;
  ALPHA := PSingle(p.g)^;
  CK    := PPtrInt(p.h)^;
  CN    := PPtrInt(p.i)^;
  N     := PPtrInt(p.j)^;
  K     := PPtrInt(p.k)^;

  kk    :=0;
  while kk < CK do begin
      nn_fast(A, B, C, ALPHA, lda, ldb, ldc,idx, CN, kk);
      //nn_stable(A, B, C, ALPHA, lda, ldb, ldc,idx, CN, kk);
      for i_d:=idx to idx+TILE_M -1 do
          for k_d:=kk to kk + TILE_K-1 do begin
              A_PART := ALPHA*A[i_d*lda + k_d];
              saxpy(N-CN, A_PART, B + k_d*ldb + CN, C+i_d*ldc + CN);
              //for j:= (N div TILE_N)*TILE_N to N-1 do
              //    C[i_d*ldc + j] := C[i_d*ldc + j] + A_PART*B[k_d*ldb + j];
          end;
      inc(kk, TILE_K)
  end;

  for kk := CK to K-1 do
      for i_d:=idx to idx+TILE_M -1 do begin
          A_PART:= ALPHA*A[i_d*lda + kk];
          saxpy(N, A_PART, B+kk*ldb, C+i_d*ldc);
          //for j:=0 to N-1 do
          //    C[i_d*ldc + j] := C[i_d*ldc + j] + A_PART*B[kk*ldb + j]
      end;
end;

procedure gemm_nn_fast(const M, N, K:IntPtr; const ALPHA:single;
            const A: PSingle; const lda:IntPtr;
            const B: PSingle; const ldb:IntPtr;
            const C: PSingle; const ldc:IntPtr);local;
var
  i, kk, CN, CM, CK:IntPtr;
  A_PART:Single;
  j, i_d, k_d: IntPtr;
  P :TMPParams;
begin
  CK := (K div TILE_K)*TILE_K;
  CM := (M div TILE_M)*TILE_M;
  CN := (N div TILE_N)*TILE_N;

  p.A :=  A     ;
  p.B :=  B     ;
  p.C :=  C     ;
  p.d :=  @lda   ;
  p.e :=  @ldb   ;
  p.f :=  @ldc   ;
  p.g :=  @ALPHA ;
  p.h :=  @CK    ;
  p.i :=  @CN    ;
  p.j :=  @N     ;
  p.k :=  @K     ;

{$ifdef USE_MULTITHREADING}
  MP.&for(nn_fastMP, 0, CM, @p, TILE_M);
{$else}
  i:=0;
  while i< CM do begin
     nn_fastMP(i, @p);
     inc(i, TILE_M)
  end;
{$endif}

  for i := CM to M-1 do
      for kk := 0 to K-1 do begin
          A_PART := ALPHA*A[i*lda + kk];
          saxpy(N, A_PART, B + kk*ldb, C + i*ldc);
          //for j := 0 to N-1 do
          //    C[i*ldc + j] := C[i*ldc + j] + A_PART*B[kk*ldb + j];
      end
end;
  {$endif}

procedure s_nt(const f, t: IntPtr; const params: Pointer);
var
  i, j, kk, K, N, lda, ldb, ldc: IntPtr;
  A, B, C: PSingle;
  ALPHA, sum: single;
  p: PMPParams absolute params;
begin
  ALPHA := PSingle(p.D)^;
  A := p.A;
  B := p.B;
  C := p.C;
  lda := PPtrInt(p.E)^;
  ldb := PPtrInt(p.F)^;
  ldc := PPtrInt(p.G)^;
  K := PPtrInt(p.K)^;
  N := PPtrInt(p.N)^;

  for i := f to t do
    for j := 0 to N - 1 do
    begin    // todo optimize nt
      //sum := 0;
      //for kk := 0 to K -1 do
      //    sum := sum + ALPHA * A[i * lda+kk] * B[j * ldb+kk];
      sum := ALPHA * sdot(K, A + i * lda, B + j * ldb);
      C[i * ldc + j] := C[i * ldc + j] + sum;
    end;
end;

procedure sgemm_nt(const M, N, K: IntPtr; const ALPHA: single;
  const A: PSingle; const lda: IntPtr; const B: PSingle; const ldb: IntPtr;
  const C: PSingle; const ldc: IntPtr); local;
var
  p: TMPParams;
begin
  p.D := @ALPHA;
  p.A := A;
  P.B := B;
  P.C := C;
  p.E := @lda;
  P.F := @ldb;
  p.G := @ldc;
  p.K := @K;
  p.N := @N;
  {$if defined(USE_MULTITHREADING)}
  mp.&For(s_nt, 0, M - 1, @p);
  {$else}
  s_nt(0, M-1, @p)
  {$endif}
end;

procedure s_tn(const f, t: IntPtr; const params: Pointer);
var
  i, j, kk, K, N, lda, ldb, ldc: SizeInt;
  A_PART, ALPHA: single;
  A, B, C: PSingle;
  p: PMPParams absolute params;
begin
  ALPHA := PSingle(p.D)^;
  A := p.A;
  B := p.B;
  C := p.C;
  lda := PIntPtr(p.E)^;
  ldb := PIntPtr(p.F)^;
  ldc := PIntPtr(p.G)^;
  K := PIntPtr(p.K)^;
  N := PIntPtr(p.N)^;

  for i := f to t do
    for kk := 0 to K - 1 do
    begin        // optimize tn
      A_PART := ALPHA * A[kk * lda + i];
      saxpy(N, A_PART, B + kk * ldb, C + i * ldc);
      //for j := 0 to N -1 do
      //    C[i * ldc+j] := C[i * ldc+j] + A_PART * B[kk * ldb+j]
    end;
end;

procedure sgemm_tn(const M, N, K: IntPtr; const ALPHA: single;
  const A: PSingle; const lda: IntPtr; const B: PSingle; const ldb: IntPtr;
  const C: PSingle; const ldc: IntPtr); local;
var
  p: TMPParams;
begin
  p.D := @ALPHA;
  p.A := A;
  P.B := B;
  P.C := C;
  p.E := @lda;
  P.F := @ldb;
  p.G := @ldc;
  p.K := @K;
  p.N := @N;
  {$if defined(USE_MULTITHREADING)}
  mp.&For(s_tn, 0, M - 1, @p);
  {$else}
  s_tn(0, M-1, @p);
  {$endif}
end;

const
  TILEN :SizeInt = 8;
  TILEK :SizeInt = 4;
  TILEM :SizeInt = 4;
procedure s_nn(const f, t: IntPtr; const ptr: pointer);
var
  i, j, kk, tj, tk, M, N, K, lda, ldb, ldc, DM, RM, DN, RN, DK ,RK: IntPtr;
  A_PART, ALPHA: single;
  p: PMPParams absolute ptr;
  A, B, C, AA, BB, CC: PSingle;
begin
  //     K          N          N
  //   [...]      [...]      [...]
  // M [.A.]  X K [.B.] => M [.C.]
  //   [...]      [...]      [...]
  ALPHA := PSingle(p.D)^;
  A := p.A;
  B := p.B;
  C := p.C;
  lda := PIntPtr(p.E)^;
  ldb := PIntPtr(p.F)^;
  ldc := PIntPtr(p.G)^;
  K := PIntPtr(p.K)^;
  N := PIntPtr(p.N)^;
  M := PIntPtr(p.M)^;

  DM := M div TILEM;
  DN := N div TILEN;
  DK := K div TILEK;

  RM := TILEM * DM;
  RN := TILEN * DN;
  RK := TILEK * DK;

  inc(C, f*ldc);
  inc(A, f*lda);
  for i := f to t do  begin   // m
    for kk := 0 to K - 1 do begin
      A_PART := ALPHA*A[kk];
      saxpy(N, A_PART, B + kk*ldb, C);
    end;
    //for kk := 0 to DK -1 do begin
    //  AA := A + kk*TILEK;
    //  for j:=0 to DN -1 do begin
    //    BB := B + kk*TILEK*ldb + j*TILEN;
    //    CC := C + j*TILEN;
    //    for tk :=0 to TILEK-1 do begin
    //      A_PART := ALPHA * AA[tk];
    //      //saxpy(TILEN, A_PART, BB, CC);
    //      for tj:=0 to TILEN -1 do
    //        CC[tj] := CC[tj] + A_PART*BB[tj];
    //      inc(BB, ldb)
    //    end;
    //  end;
    //  for tk :=0 to TILEK-1 do begin
    //    A_PART := ALPHA * AA[tk];
    //    BB := B + (kk*TILEK + tk)*ldb + RN;
    //    CC := C + RN;
    //    //saxpy(N - RN, A_PART, BB, C);
    //    for j:= 0 to N - RN -1 do
    //      CC[j] := CC[j] + A_PART*BB[j];
    //  end;
    //end;
    //for tk := RK to K - 1 do begin
    //  A_PART := ALPHA*A[tk];
    //  BB := B + tk*ldb;
    //  //saxpy(N, A_PART, BB, C);
    //  for j:= 0 to N -1 do
    //    C[j] := C[j] + A_PART*BB[j]
    //end;

    inc(C, ldc);
    inc(A, lda)
  end;
end;


procedure sgemm_nn(
  const M, N, K: IntPtr; const ALPHA: single;
  const A: PSingle; const lda: IntPtr;
  const B: PSingle; const ldb: IntPtr;
  const C: PSingle; const ldc: IntPtr); inline;
var
  p: TMPParams;
begin
  p.D := @ALPHA;
  p.A := A;
  P.B := B;
  P.C := C;
  p.E := @lda;
  P.F := @ldb;
  p.G := @ldc;
  p.K := @K;
  p.N := @N;
  p.M := @M;
  {$if defined(USE_MULTITHREADING)}
  mp.&for(s_nn, 0, M - 1, @p);
  {$else}
  s_nn(0, M-1, @p)
  {$endif}
end;

procedure s_tt(const f, t: IntPtr; const params: Pointer);
var
  i, j, kk, K, N, lda, ldb, ldc: SizeInt;
  sum, ALPHA: single;
  A, B, C: PSingle;
  p: PMPParams absolute params;
begin
  ALPHA := PSingle(p.D)^;
  A := p.A;
  B := p.B;
  C := p.C;
  lda := PIntPtr(p.E)^;
  ldb := PIntPtr(p.F)^;
  ldc := PIntPtr(p.G)^;
  K := PIntPtr(p.K)^;
  N := PIntPtr(p.N)^;

  for i := f to t do
    for j := 0 to N - 1 do
    begin           // todo optimize tt
      sum := 0;
      for kk := 0 to K - 1 do
        sum := sum + ALPHA * A[i + kk * lda] * B[kk + j * ldb];
      C[i * ldc + j] := C[i * ldc + j] + sum;
    end;
end;

procedure sgemm_tt(const M, N, K: IntPtr; const ALPHA: single;
  const A: PSingle; const lda: IntPtr; const B: PSingle; const ldb: IntPtr;
  const C: PSingle; const ldc: IntPtr); local;
var
  p: TMPParams;
begin
  p.D := @ALPHA;
  p.A := A;
  P.B := B;
  P.C := C;
  p.E := @lda;
  P.F := @ldb;
  p.G := @ldc;
  p.K := @K;
  p.N := @N;
  {$if defined(USE_MULTITHREADING)}
  mp.&For(s_tt, 0, M - 1, @p);
  {$else}
  s_tt(0, M-2, @p);
  {$endif}
end;

function cblas_sdot(const N: SizeInt; const A: PSingle; const inca: SizeInt;
  const B: PSingle; const incb: SizeInt): single;
var
  i: SizeInt;
begin
  if (inca = 1) and (incb = 1) then
  begin
    Result := sdot(N, A, B);
    exit;
  end;
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + A[i * inca] * B[i * incb];
end;

function cblas_ddot(const N: SizeInt; const A: PDouble; const inca: SizeInt;
  const B: PDouble; const incb: SizeInt): double;
var
  i: SizeInt;
begin
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + A[i * inca] * B[i * incb];
end;

procedure cblas_sgemm(const Order: CBLAS_LAYOUT; const TransA, TransB: CBLAS_TRANSPOSE;
  const M, N, K: SizeInt; const ALPHA: single; const A: PSingle;
  const lda: SizeInt; const B: PSingle; const ldb: SizeInt; const BETA: single;
  const C: PSingle; const ldc: SizeInt);
var
  row, col, i, j: SizeInt;
begin

  {$ifdef _USE_TELEMETRY}
  if benchmark then metrics.ops.start(opGemm);
  {$endif}

  //     K          N          N
  //   [...]      [...]      [...]
  // M [.A.]  X K [.B.] => M [.C.]
  //   [...]      [...]      [...]


  if beta <> 1 then
    for i := 0 to M - 1 do
      TSingleTensor.mulvs(N, beta, pointer(C + i * ldc), 1);
  //for j := 0 to N -1 do
  //  C[i * ldc+j] := C[i * ldc+j] * BETA;


  if (TransA = CblasNoTrans) and (TransB = CblasNoTrans) then
  // todo fast_gemm is disabled, not 100% accurate!
  {$if defined(BIG_MATRECIES)} // optimized for big matrecies! it will perform close to openblas speed, [CAUSION] : unstable with small matrecies!
    if AVX2Support then
      gemm_nn_fast(M, N, K, ALPHA, A, lda, B, ldb, C, ldc)
    else
  {$endif}
      sgemm_nn(M, N, K, ALPHA, A, lda, B, ldb, C, ldc)
  else if (TransA = CblasNoTrans) and (TransB = CblasTrans) then
    sgemm_nt(M, N, K, ALPHA, A, lda, B, ldb, C, ldc)
  else if (TransA = CblasTrans) and (TransB = CblasNoTrans) then
    sgemm_tn(M, N, K, ALPHA, A, lda, B, ldb, C, ldc)
  else if (TransA = CblasTrans) and (TransB = CblasTrans) then
    sgemm_tt(M, N, K, ALPHA, A, lda, B, ldb, C, ldc);
  {$ifdef _USE_TELEMETRY}
  if benchmark then metrics.ops.finish(opGemm);
  {$endif}
end;

procedure cblas_dgemm(const Order: CBLAS_LAYOUT; const TransA, TransB: CBLAS_TRANSPOSE;
  const M, N, K: SizeInt; const ALPHA: double; const A: PDouble;
  const lda: SizeInt; const B: PDouble; const ldb: SizeInt; const BETA: double;
  const C: PDouble; const ldc: SizeInt);
var
  i, kk, j: SizeInt;
  A_PART: double;
  AA, BB, CC: PDouble;
begin
  // todo [dgemm] Naive implementation, needs optimization
  if beta <> 1 then
    for i := 0 to M - 1 do
      TDoubleTensor.mulvs(N, BETA, pointer(C + i * ldc), 1);
  //for j := 0 to N -1 do
  //  C[i * ldc+j] := C[i * ldc+j] * BETA;

  if (TransA = CblasNoTrans) and (TransB = CblasNoTrans) then
    for i := 0 to M - 1 do
    begin
      AA := A + i * lda;
      CC := C + i * ldc;
      for kk := 0 to K - 1 do
      begin
        A_PART := ALPHA * AA[kk];
        BB := B + kk * ldb;
        daxpy(N, A_PART, BB, CC);
        //for j:=0 to N-1 do
        //    CC[j]:=CC[j] + A_PART*BB[j]
      end;
    end
  else if (TransA = CblasNoTrans) and (TransB = CblasTrans) then
    for i := 0 to M - 1 do
      for j := 0 to N - 1 do
        C[i * ldc + j] := ALPHA * ddot(K, A + i * lda, B + j * ldb)
  //for kk := 0 to K -1 do
  //    C[i*ldc + j] := C[i*ldc + j] + ALPHA * A[i * lda + kk]*B[j*ldb + kk]
  else if (TransA = CblasTrans) and (TransB = CblasNoTrans) then
    for i := 0 to M - 1 do
    begin
      CC := C + i * ldc;
      AA := A + i;
      for kk := 0 to K - 1 do
      begin
        A_PART := ALPHA * AA[kk * lda];
        daxpy(N, A_PART, B + kk * ldb, CC);
        //for j:=0 to N-1 do
        //    C[i*ldc + j] := C[i*ldc + j] + A_PART*B[kk*ldb + j]
      end;
    end
  else if (TransA = CblasTrans) and (TransB = CblasTrans) then
    for i := 0 to M - 1 do
      for j := 0 to N - 1 do
        for kk := 0 to K - 1 do
          C[i * ldc + j] := C[i * ldc + j] + ALPHA * A[kk * lda + i] * B[j * ldb + kk];
end;

procedure cblas_saxpy(const N: SizeInt; const alpha: single; const X: PSingle;
  const INCX: SizeInt; const Y: PSingle; const INCY: SizeInt);
var
  i: SizeInt;
begin
  if (INCX = 1) and (INCY = 1) then
  begin
    saxpy(N, alpha, X, Y);
    exit;
  end;
  for i := 0 to N - 1 do
    y[i * INCY] := alpha * x[i * INCX] + y[i * INCY];
end;

procedure cblas_daxpy(const N: SizeInt; const alpha: double; const X: PDouble;
  const incX: SizeInt; const Y: PDouble; const incY: SizeInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[i * INCY] := alpha * x[i * INCX] + y[i * INCY];
end;

class function TensorUtils.lerp(const ratio, a, b: single): single;
begin
  Result := a + ratio * (b - a);
end;

class procedure TensorUtils.swap(var a, b: single);
var
  tm: single;
begin
  tm := a;
  a := b;
  b := tm;
end;

class function TensorUtils.Gaussian(const u, sig, x: single): single;
begin
  Result := Exp(-0.5 * sqr(x - u) / sqr(sig)) / (sig * sqrtPIx2);
end;

class function TensorUtils.Gaussian2d(const u, sig, x, y: single): single;
begin
  Result := Exp(-0.5 * (sqr(x - u) + sqr(y - u)) / sqr(sig)) / (sig * sqrtPIx2);
end;

class function TensorUtils.Phytha2d(const R, x, y: single): single;
begin
  Result := Sqr(r) - (sqr(x - r) + sqr(y - r));
end;

class function TensorUtils.lerp(const ratio, a, b: double): double;
begin
  Result := a + ratio * (b - a);
end;

class procedure TensorUtils.swap(var a, b: double);
var
  tm: single;
begin
  tm := a;
  a := b;
  b := tm;
end;

class function TensorUtils.Gaussian(const u, sig, x: double): double;
begin
  Result := Exp(-0.5 * sqr(x - u) / sqr(sig)) / (sig * sqrtPIx2);
end;

class function TensorUtils.Gaussian2d(const u, sig, x, y: double): double;
begin
  Result := Exp(-0.5 * (sqr(x - u) + sqr(y - u)) / sqr(sig)) / (sig * sqrtPIx2);
end;

class function TensorUtils.Phytha2d(const R, x, y: double): double;
begin
  Result := Sqr(r) - (sqr(x - r) + sqr(y - r));
end;

class procedure TensorUtils.get_embedding(const src: PSingle;
  const src_w, src_h, src_c, embedding_size, cur_w, cur_h, cur_n, cur_b: SizeInt;
  dst: PSingle);
var
  i, stride: SizeInt;
  S: PSingle;
begin
  S := src + cur_b * (src_c * src_h * src_w) + cur_n * (embedding_size * src_h * src_w) +
    cur_h * src_w + cur_w;
  stride := src_h * src_w;
  for i := 0 to embedding_size - 1 do
    dst[i] := S[i * stride];
end;

class procedure TensorUtils.openPicture(const filename: string);
begin
  {$if defined(MSWINDOWS)}
  ShellExecute(0, 'open', pchar(filename), '', '', 0);
  {$endif}
end;

{ TTools }

class procedure TTools<T>.QuickSort(Arr: PT; L, R: SizeInt;
  const Compare: TComparefunc; const Descending: boolean);
var
  I, J, neg: longint;
  P, Q: T;
begin
  if not Assigned(Arr) then exit;

  if descending then
    neg := -1
  else
    neg := 1;
  repeat
    I := L;
    J := R;
    P := Arr[(L + R) shr 1];
    repeat
      while (neg * Compare(P, Arr[I]) > 0) and (I<=R) do
        inc(I);
      while (neg * Compare(P, Arr[J]) < 0) and (J>=0) do
        dec(J);
      if I <= J then
      begin
        Q := Arr[I];
        Arr[I] := Arr[J];
        Arr[J] := Q;
        I := I + 1;
        J := J - 1;
      end;
    until I > J;
    if J - L < R - I then
    begin
      if L < J then
        QuickSort(Arr, L, J, Compare, Descending);
      L := I;
    end
    else
    begin
      if I < R then
        QuickSort(Arr, I, R, Compare, Descending);
      R := J;
    end;
  until L >= R;
end;

procedure _and(const N: SizeInt; const x: PInt32; const incx: SizeInt;
  const y: PInt32; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: PInt64; const incx: SizeInt;
  const y: PInt64; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: pbyte; const incx: SizeInt;
  const y: pbyte; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: PShortInt; const incx: SizeInt;
  const y: PShortInt; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] and y[incy * i];
end;

procedure _or(const N: SizeInt; const x: PInt32; const incx: SizeInt;
  const y: PInt32; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: PInt64; const incx: SizeInt;
  const y: PInt64; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: pbyte; const incx: SizeInt;
  const y: pbyte; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: PShortInt; const incx: SizeInt;
  const y: PShortInt; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] or y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: PInt32; const incx: SizeInt;
  const y: PInt32; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: PInt64; const incx: SizeInt;
  const y: PInt64; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: pbyte; const incx: SizeInt;
  const y: pbyte; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: PShortInt; const incx: SizeInt;
  const y: PShortInt; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    x[incx * i] := x[incx * i] xor y[incy * i];
end;

procedure _and(const N: SizeInt; const x: int32; const y: PInt32;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: int64; const y: PInt64;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: byte; const y: pbyte;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x and y[incy * i];
end;

procedure _and(const N: SizeInt; const x: shortint; const y: PShortInt;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x and y[incy * i];
end;

procedure _or(const N: SizeInt; const x: int32; const y: PInt32;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: int64; const y: PInt64;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: byte; const y: pbyte;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x or y[incy * i];
end;

procedure _or(const N: SizeInt; const x: shortint; const y: PShortInt;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x or y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: int32; const y: PInt32;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: int64; const y: PInt64;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: byte; const y: pbyte;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x xor y[incy * i];
end;

procedure _xor(const N: SizeInt; const x: shortint; const y: PShortInt;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := x xor y[incy * i];
end;

procedure _shr(const N: SizeInt; const x: int32; const y: PInt32;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shr x;
end;

procedure _shr(const N: SizeInt; const x: int64; const y: PInt64;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shr x;
end;

procedure _shr(const N: SizeInt; const x: byte; const y: pbyte;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shr x;
end;

procedure _shr(const N: SizeInt; const x: shortint; const y: PShortInt;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shr x;
end;

procedure _shl(const N: SizeInt; const x: int32; const y: PInt32;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shl x;
end;

procedure _shl(const N: SizeInt; const x: int64; const y: PInt64;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shl x;
end;

procedure _shl(const N: SizeInt; const x: byte; const y: pbyte;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shl x;
end;

procedure _shl(const N: SizeInt; const x: shortint; const y: PShortInt;
  const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := y[incy * i] shl x;
end;

procedure _not(const N: SizeInt; const x: Pint32; const incx: SizeInt;
  const y: PInt32; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := not x[incx * i];
end;

procedure _not(const N: SizeInt; const x: PInt64; const incx: SizeInt;
  const y: PInt64; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := not x[incx * i];
end;

procedure _not(const N: SizeInt; const x: pbyte; const incx: SizeInt;
  const y: pbyte; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := not x[incx * i];
end;

procedure _not(const N: SizeInt; const x: PShortInt; const incx: SizeInt;
  const y: PShortInt; const incy: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    y[incy * i] := not x[incx * i];
end;

procedure srnd(const v:uint32);
begin
  rand_seed := v
end;

function rnd():integer;
begin
	rand_seed := rand_seed xor (rand_seed shl 13);
	rand_seed := rand_seed xor (rand_seed shr 17);
	rand_seed := rand_seed xor (rand_seed shl 5 );
        result := (rand_seed mod $7FFFFFFF);
end;

function _rand(const a: single): single; overload; inline;
begin
  Result := a * (rnd()/$7FFFFFFF);
end;

function _rand(const a: double): double; overload; inline;
begin
  Result := a * random();
end;

function _rand(const a: int32): int32; overload; inline;
begin
  Result := random(a);
end;

function _rand(const a: int64): int64; overload; inline;
begin
  Result := random(a);
end;

function _rand(const a: byte): byte; overload; inline;
begin
  Result := random(a);
end;

function _rand(const a: shortint): shortint; overload; inline;
begin
  Result := random(a);
end;

function _randG(const aMean, aStdDev: single): single; overload; inline;
begin
  Result := randG(aMean, aStdDev);
end;

function _randG(const aMean, aStdDev: double): double; overload; inline;
begin
  Result := randG(aMean, aStdDev);
end;

function _randG(const aMean, aStdDev: int32): int32; overload; inline;
begin
  Result := round(randG(aMean, aStdDev));
end;

function _randG(const aMean, aStdDev: int64): int64; overload; inline;
begin
  Result := round(randG(aMean, aStdDev));
end;

function _randG(const aMean, aStdDev: byte): byte; overload; inline;
begin
  Result := round(randG(aMean, aStdDev));
end;

function _randG(const aMean, aStdDev: shortint): shortint; overload; inline;
begin
  Result := round(randG(aMean, aStdDev));
end;

function _cmp(const a, b: single): SizeInt; overload; inline;
begin
  if a=b then exit(0);
  if a > b then exit(1);
  result :=-1;
  //if a < b then exit(-1);
end;

function _cmp(const a, b: double): SizeInt; overload; inline;
begin
  if a=b then exit(0);
  if a > b then exit(1);
  //if a < b then exit(-1);
  result :=-1;
end;

function _cmp(const a, b: int32): SizeInt; overload; inline;
begin
  Result := a - b;
end;

function _cmp(const a, b: int64): SizeInt; overload; inline;
begin
  Result := a - b;
end;

function _cmp(const a, b: byte): SizeInt; overload; inline;
begin
  Result := a - b;
end;

function _cmp(const a, b: shortint): SizeInt; overload; inline;
begin
  Result := a - b;
end;


function _Plus(const a, b: single): single; overload; inline;
begin
  Result := a + b;
end;

function _Plus(const a, b: double): double; overload; inline;
begin
  Result := a + b;
end;

function _Plus(const a, b: int32): int32; overload; inline;
begin
  Result := a + b;
end;

function _Plus(const a, b: int64): int64; overload; inline;
begin
  Result := a + b;
end;

function _Plus(const a, b: byte): byte; overload; inline;
begin
  Result := a + b;
end;

function _Plus(const a, b: shortint): shortint; overload; inline;
begin
  Result := a + b;
end;

function _Minus(const a, b: single): single; overload; inline;
begin
  Result := a - b;
end;

function _Minus(const a, b: double): double; overload; inline;
begin
  Result := a - b;
end;

function _Minus(const a, b: int32): int32; overload; inline;
begin
  Result := a - b;
end;

function _Minus(const a, b: int64): int64; overload; inline;
begin
  Result := a - b;
end;

function _Minus(const a, b: byte): byte; overload; inline;
begin
  Result := a - b;
end;

function _Minus(const a, b: shortint): shortint; overload; inline;
begin
  Result := a - b;
end;

function _Times(const a, b: single): single; overload; inline;
begin
  Result := a * b;
end;

function _Times(const a, b: double): double; overload; inline;
begin
  Result := a * b;
end;

function _Times(const a, b: int32): int32; overload; inline;
begin
  Result := a * b;
end;

function _Times(const a, b: int64): int64; overload; inline;
begin
  Result := a * b;
end;

function _Times(const a, b: byte): byte; overload; inline;
begin
  Result := a * b;
end;

function _Times(const a, b: shortint): shortint; overload; inline;
begin
  Result := a * b;
end;

function _Division(const a, b: single): single; overload; inline;
begin
  Result := a / b;
end;

function _Division(const a, b: double): double; overload; inline;
begin
  Result := a / b;
end;

function _Division(const a, b: int32): int32; overload; inline;
begin
  Result := a div b;
end;

function _Division(const a, b: int64): int64; overload; inline;
begin
  Result := a div b;
end;

function _Division(const a, b: byte): byte; overload; inline;
begin
  Result := a div b;
end;

function _Division(const a, b: shortint): shortint; overload; inline;
begin
  Result := a div b;
end;

function _Abs(const a: single): single; overload; inline;
begin
  Result := abs(a);
end;

function _Abs(const a: double): double; overload; inline;
begin
  Result := abs(a);
end;

function _Abs(const a: int32): int32; overload; inline;
begin
  Result := abs(a);
end;

function _Abs(const a: int64): int64; overload; inline;
begin
  Result := abs(a);
end;

function _Abs(const a: byte): byte; overload; inline;
begin
  Result := abs(a);
end;

function _Abs(const a: shortint): shortint; overload; inline;
begin
  Result := abs(a);
end;

function _Sqr(const a: single): single; overload; inline;
begin
  Result := a * a;
end;

function _Sqr(const a: double): double; overload; inline;
begin
  Result := a * a;
end;

function _Sqr(const a: int32): int32; overload; inline;
begin
  Result := a * a;
end;

function _Sqr(const a: int64): int64; overload; inline;
begin
  Result := a * a;
end;

function _Sqr(const a: byte): byte; overload; inline;
begin
  Result := a * a;
end;

function _Sqr(const a: shortint): shortint; overload; inline;
begin
  Result := a * a;
end;

function _Sqrt(const a: single): single; overload; inline;
begin
  Result := sqrt(a);
end;

function _Sqrt(const a: double): double; overload; inline;
begin
  Result := sqrt(a);
end;

function _Sqrt(const a: int32): int32; overload; inline;
begin
  Result := round(sqrt(a));
end;

function _Sqrt(const a: int64): int64; overload; inline;
begin
  Result := round(sqrt(a));
end;

function _Sqrt(const a: byte): byte; overload; inline;
begin
  Result := round(sqrt(a));
end;

function _Sqrt(const a: shortint): shortint; overload; inline;
begin
  Result := round(sqrt(a));
end;

function _exp(const a: single): single; overload; inline;
begin
  Result := exp(a);
end;

function _exp(const a: double): double; overload; inline;
begin
  Result := exp(a);
end;

function _exp(const a: int32): int32; overload; inline;
begin
  Result := round(exp(a));
end;

function _exp(const a: int64): int64; overload; inline;
begin
  Result := round(exp(a));
end;

function _exp(const a: byte): byte; overload; inline;
begin
  Result := round(exp(a));
end;

function _exp(const a: shortint): shortint; overload; inline;
begin
  Result := round(exp(a));
end;

function _ln(const a: single): single; overload; inline;
begin
  Result := ln(a);
end;

function _ln(const a: double): double; overload; inline;
begin
  Result := ln(a);
end;

function _ln(const a: int32): int32; overload; inline;
begin
  Result := round(ln(a));
end;

function _ln(const a: int64): int64; overload; inline;
begin
  Result := round(ln(a));
end;

function _ln(const a: byte): byte; overload; inline;
begin
  Result := round(ln(a));
end;

function _ln(const a: shortint): shortint; overload; inline;
begin
  Result := round(ln(a));
end;

function Casts(const a: SizeInt): single; overload; inline;
begin
  Result := a;
end;

function Castd(const a: SizeInt): double; overload; inline;
begin
  Result := a;
end;

function Casti32(const a: SizeInt): int32; overload; inline;
begin
  Result := a;
end;

function Casti64(const a: SizeInt): int64; overload; inline;
begin
  Result := a;
end;

function Castu8(const a: SizeInt): byte; overload; inline;
begin
  Result := a;
end;

function Casti8(const a: SizeInt): shortint; overload; inline;
begin
  Result := a;
end;

function _toStr(const v: single): string; overload; inline;
begin
  str(v: 1: sDigits, Result);
end;

function _toStr(const v: double): string; overload; inline;
begin
  str(v: 1: sDigits, Result);
end;

function _toStr(const v: shortint): string; overload; inline;
begin
  str(v: 1, Result);
end;

function _toStr(const v: smallint): string; overload; inline;
begin
  str(v: 1, Result);
end;

function _toStr(const v: int32): string; overload; inline;
begin
  str(v: 1, Result);
end;

function _toStr(const v: int64): string; overload; inline;
begin
  str(v: 1, Result);
end;

function _toStr(const v: byte): string; overload; inline;
begin
  str(v: 1, Result);
end;


procedure sfmavss(const N: SizeInt; const src: PSingle; const stride: SizeInt;
  const scale, bias: single);
var
  i: SizeInt;
begin
  if stride = 1 then
  begin
    for i := 0 to N - 1 do
      src[i] := src[i] * scale + bias;
    exit;
  end;
  for i := 0 to N - 1 do
    src[i * stride] := src[i * stride] * scale + bias;
end;

procedure dfmavss(const N: SizeInt; const src: PDouble; const stride: SizeInt;
  const scale, bias: double);
var
  i: SizeInt;
begin
  if stride = 1 then
  begin
    for i := 0 to N - 1 do
      src[i] := src[i] * scale + bias;
    exit;
  end;
  for i := 0 to N - 1 do
    src[i * stride] := src[i * stride] * scale + bias;
end;

procedure vAbsI(const N: SizeInt; const a: PSingle; const INCA: SizeInt;
  const b: PSingle; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA]);
end;

procedure vAbsI(const N: SizeInt; const a: PDouble; const INCA: SizeInt;
  const b: PDouble; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA]);
end;

procedure vAbsI(const N: SizeInt; const a: PInt32; const INCA: SizeInt;
  const b: PInt32; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA]);
end;

procedure vAbsI(const N: SizeInt; const a: PInt64; const INCA: SizeInt;
  const b: PInt64; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA]);
end;

procedure vAbsDiffI(const N: SizeInt; const a: PSingle; const INCA: SizeInt;
  const b: PSingle; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA] - b[i * INCB]);
end;

procedure vAbsDiffI(const N: SizeInt; const a: PDouble; const INCA: SizeInt;
  const b: PDouble; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA] - b[i * INCB]);
end;

procedure vAbsDiffI(const N: SizeInt; const a: PInt32; const INCA: SizeInt;
  const b: PInt32; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA] - b[i * INCB]);
end;

procedure vAbsDiffI(const N: SizeInt; const a: PInt64; const INCA: SizeInt;
  const b: PInt64; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA] - b[i * INCB]);
end;

procedure vAbsDiffI(const N: SizeInt; const a: pbyte; const INCA: SizeInt;
  const b: pbyte; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := abs(a[i * INCA] - b[i * INCB]);
end;

procedure vSqrI(const N: SizeInt; const a: PSingle; const INCA: SizeInt;
  const b: PSingle; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := a[i * INCA] * a[i * INCA];
end;

procedure vSqrI(const N: SizeInt; const a: PDouble; const INCA: SizeInt;
  const b: PDouble; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := a[i * INCA] * a[i * INCA];
end;

procedure vSqrI(const N: SizeInt; const a: PInt32; const INCA: SizeInt;
  const b: PInt32; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := a[i * INCA] * a[i * INCA];
end;

procedure vSqrI(const N: SizeInt; const a: PInt64; const INCA: SizeInt;
  const b: PInt64; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := a[i * INCA] * a[i * INCA];
end;

procedure vSqrI(const N: SizeInt; const a: pbyte; const INCA: SizeInt;
  const b: pbyte; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := a[i * INCA] * a[i * INCA];
end;

procedure vSqrtI(const N: SizeInt; const a: PSingle; const INCA: SizeInt;
  const b: PSingle; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := sqrt(a[i * INCA]);
end;

procedure vSqrtI(const N: SizeInt; const a: PDouble; const INCA: SizeInt;
  const b: PDouble; const INCB: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    b[i * INCB] := sqrt(a[i * INCA]);
end;

{$if defined(CPUX64)}
procedure vsAdd_avx2(const N:SizeInt; const A, B, C:PSingle);assembler;
asm
  mov          rax      ,    N
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vmovups      ymm0     ,    yword [A]
  vaddps       ymm1     ,    ymm0,  yword [B]
  vmovups      yword[C] ,    ymm1
  add          A        ,    8*4
  add          B        ,    8*4
  add          C        ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
@while2:
  vmovss       xmm0     ,    dword [A]
  vaddss       xmm1     ,    xmm0,  dword [B]
  vmovss       dword[C] ,    xmm1
  add          A        ,    4
  add          B        ,    4
  add          C        ,    4
  dec          rax
  jnz         @while2
@done:
end;

function vssum_avx2(const N:SizeInt; const A:PSingle):single;assembler;
asm
  mov          r8       ,    N
  shr          r8       ,    3  // div 8
  vxorps       ymm0     ,    ymm0,  ymm0
  jz           @rem1
@while1:

  vaddps       ymm0     ,    ymm0,  yword [A]
  add          A        ,    8*4
  dec          r8
  jnz         @while1

@rem1:
  vextractf128 xmm1     ,    ymm0,  1
  vzeroupper
  addps        xmm0     ,    xmm1
  haddps       xmm0     ,    xmm0
  haddps       xmm0     ,    xmm0
  mov          r8       ,    N
  and          r8       ,    7
  jz           @done
@while2:
  vaddss       xmm0     ,    xmm0,  dword [A]
  add          A        ,    4
  dec          r8
  jnz         @while2
@done:
end;

{$endif}

function vsSumI(const N:SizeInt; const src:PSingle; const stride:SizeInt):single;
var i:SizeInt;
begin
  {$if defined(CPUX64)}
  if AVX2Support and (stride=1) then
    exit(vssum_avx2(N, src));
  {$endif}
  result := 0;
  for i:=0 to N-1 do
    result := result + src[i*stride]
end;

function vdSumI(const N:SizeInt; const src:PSingle; const stride:SizeInt):single;
var i:SizeInt;
begin
  result := 0;
  for i:=0 to N-1 do
    result := result + src[i*stride]
end;

function vsRSS(const N: SizeInt; const mean: single; const src: PSingle; const stride: SizeInt):single;
var i:Sizeint;
begin
  {$ifdef CPUX64}
  if AVX2Support and (stride=1) then
    exit(srss(N, mean, src));
  {$endif}
  result :=0;
  for i:=0 to N-1 do
    result := result + sqr(src[i*stride] - mean);
end;

function vdRSS(const N: SizeInt; const mean: double; const src: PDouble; const stride: SizeInt):double;
var i:Sizeint;
begin
  result :=0;
  for i:=0 to N-1 do
    result := result + sqr(src[i*stride] - mean);
end;

procedure vsAddI(const N: SizeInt; const a: PSingle; const inca: SizeInt;
  const b: PSingle; const incb: SizeInt; const c: PSingle; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin
  {$if defined(CPUX64)}
  if AVX2Support and (inca=1) and (incb=1) and (incc=1) then
    vsAdd_avx2(N, A, B, C)
  else
  {$endif}
  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] + b[i * incb];

end;

procedure vsSubI(const N: SizeInt; const a: PSingle; const inca: SizeInt;
  const b: PSingle; const incb: SizeInt; const c: PSingle; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] - b[i * incb];

end;

procedure vsMulI(const N: SizeInt; const a: PSingle; const inca: SizeInt;
  const b: PSingle; const incb: SizeInt; const c: PSingle; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] * b[i * incb];

end;

procedure vsDivI(const N: SizeInt; const a: PSingle; const inca: SizeInt;
  const b: PSingle; const incb: SizeInt; const c: PSingle; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] / b[i * incb];

end;

procedure vdAddI(const N: SizeInt; const a: PDouble; const inca: SizeInt;
  const b: PDouble; const incb: SizeInt; const c: PDouble; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] + b[i * incb];

end;

procedure vdSubI(const N: SizeInt; const a: PDouble; const inca: SizeInt;
  const b: PDouble; const incb: SizeInt; const c: PDouble; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] - b[i * incb];

end;

procedure vdMulI(const N: SizeInt; const a: PDouble; const inca: SizeInt;
  const b: PDouble; const incb: SizeInt; const c: PDouble; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] * b[i * incb];

end;

procedure vdDivI(const N: SizeInt; const a: PDouble; const inca: SizeInt;
  const b: PDouble; const incb: SizeInt; const c: PDouble; const incc: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := a[i * inca] / b[i * incb];

end;

{$if defined(CPUX64)}
procedure vssAddI_avx(const N:SizeInt; const ALPHA:Single; const B:PSingle; C:PSingle);assembler;
asm
  mov          rax       ,    N
  vbroadcastss ymm0      ,    ALPHA
//  shr          rax       ,    5  // div 32
//  jz           @rem
//
//@while:
//  vaddps       ymm1          ,    ymm0,  yword [B]
//  vaddps       ymm2          ,    ymm0,  yword [B+1*8]
//  vaddps       ymm3          ,    ymm0,  yword [B+2*8]
//  vaddps       ymm4          ,    ymm0,  yword [B+3*8]
//  vmovups      yword [C]     ,    ymm1
//  vmovups      yword [C+1*8] ,    ymm2
//  vmovups      yword [C+2*8] ,    ymm3
//  vmovups      yword [C+3*8] ,    ymm4
//
//  add          B        ,    8*4*4
//  add          C        ,    8*4*4
//  dec          rax
//  jnz         @while
//
//@rem:
//  mov          rax       ,    N
//  and          rax       ,    31
  shr          rax       ,    3 // div 8
  jz           @rem1

@while1:
  vaddps       ymm1      ,    ymm0,  yword [B]
  vmovups      yword [C] ,    ymm1
  add          B         ,    8*4
  add          C         ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
@while2:
  vaddss       xmm1     ,    xmm0,  dword [B]
  vmovss       dword[C] ,    xmm1
  add          B        ,    4
  add          C        ,    4
  dec          rax
  jnz         @while2
@done:
end;

procedure vssMulI_avx(const N:SizeInt; const ALPHA:Single; const B:PSingle; C:PSingle);assembler;
asm
  mov          rax       ,    N
  vbroadcastss ymm0      ,    ALPHA
//  shr          rax       ,    5  // div 32
//  jz           @rem
//
//@while:
//  vmulps       ymm1          ,    ymm0,  yword [B]
//  vmulps       ymm2          ,    ymm0,  yword [B+1*8]
//  vmulps       ymm3          ,    ymm0,  yword [B+2*8]
//  vmulps       ymm4          ,    ymm0,  yword [B+3*8]
//  vmovups      yword [C]     ,    ymm1
//  vmovups      yword [C+1*8] ,    ymm2
//  vmovups      yword [C+2*8] ,    ymm3
//  vmovups      yword [C+3*8] ,    ymm4
//
//  add          B        ,    8*4*4
//  add          C        ,    8*4*4
//  dec          rax
//  jnz         @while
//
//@rem:
//  mov          rax       ,    N
//  and          rax       ,    31
  shr          rax       ,    3 // div 8
  jz           @rem1

@while1:
  vmulps       ymm1      ,    ymm0,  yword [B]
  vmovups      yword [C] ,    ymm1
  add          B         ,    8*4
  add          C         ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
@while2:
  vmulss       xmm1     ,    xmm0,  dword [B]
  vmovss       dword[C] ,    xmm1
  add          B        ,    4
  add          C        ,    4
  dec          rax
  jnz         @while2
@done:
end;

//procedure vssMulAddI_avx(const N:SizeInt; const ALPHA, BETA:Single; const B:PSingle; C:PSingle);
//var i:SizeInt;
//begin
//  for i:=0 to N-1 do
//    C[i] := B[i]*ALPHA + BETA
//end;


procedure vssMulAddI_avx(const N:SizeInt; const ALPHA, BETA:Single; const B:PSingle; C:PSingle); assembler;
asm
  mov          rax       ,    N
  vbroadcastss ymm0      ,    ALPHA
  vbroadcastss ymm1      ,    BETA

//  shr          rax       ,    5  // div 32
//  jz           @rem
//
//@while:
//  vmulps       ymm2          ,    ymm0,  yword [B]
//  vmulps       ymm3          ,    ymm0,  yword [B+1*8]
//  vmulps       ymm4          ,    ymm0,  yword [B+2*8]
//  vmulps       ymm5          ,    ymm0,  yword [B+3*8]
//  vaddps       ymm2          ,    ymm1,  ymm2
//  vaddps       ymm3          ,    ymm1,  ymm3
//  vaddps       ymm4          ,    ymm1,  ymm4
//  vaddps       ymm5          ,    ymm1,  ymm5
//  vmovups      yword [C]     ,    ymm2
//  vmovups      yword [C+1*8] ,    ymm3
//  vmovups      yword [C+2*8] ,    ymm4
//  vmovups      yword [C+3*8] ,    ymm5
//
//  add          B        ,    8*4*4
//  add          C        ,    8*4*4
//  dec          rax
//  jnz         @while
//
//@rem:
//  mov          rax       ,    N
//  and          rax       ,    31
  shr          rax       ,    3 // div 8
  jz           @rem1

@while1:
  vmovups      ymm3      ,    ymm1
  vfmadd231ps  ymm3      ,    ymm0,  yword [B]
  //vmulps       ymm3      ,    ymm0,  yword [B]
  //vaddps       ymm3      ,    ymm1,  ymm3
  vmovups      yword [C] ,    ymm3
  add          B         ,    8*4
  add          C         ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
  vzeroupper
@while2:
  movss        xmm3      ,    xmm1
  vfmadd231ss  xmm3      ,    xmm0,  yword [B]
  //vmulss       xmm3     ,    xmm0,  dword [B]
  //vaddss       xmm3     ,    xmm1,  xmm3

  vmovss       dword[C] ,    xmm3
  add          B        ,    4
  add          C        ,    4
  dec          rax
  jnz         @while2
@done:
end;

{$endif}



procedure vssAddI(const N: SizeInt; const ALPHA: single; const b: PSingle;
  const incb: SizeInt; const c: PSingle; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  {$if defined(CPUX64)}
  if AVX2Support and (incb=1) and (incc=1) then
     vssAddI_avx(N, ALPHA, B, C)
  else
  {$endif}
  for i := 0 to N - 1 do
    c[i * incc] := ALPHA + b[i * incb];
end;

procedure vssSubI(const N: SizeInt; const ALPHA: single; const b: PSingle;
  const incb: SizeInt; const c: PSingle; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA - b[i * incb];

end;

procedure vssMulI(const N: SizeInt; const ALPHA: single; const b: PSingle;
  const incb: SizeInt; const c: PSingle; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA * b[i * incb];

end;

procedure vssDivI(const N: SizeInt; const ALPHA: single; const b: PSingle;
  const incb: SizeInt; const c: PSingle; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA / b[i * incb];

end;

procedure vdsAddI(const N: SizeInt; const ALPHA: double; const b: PDouble;
  const incb: SizeInt; const c: PDouble; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA + b[i * incb];

end;

procedure vdsSubI(const N: SizeInt; const ALPHA: double; const b: PDouble;
  const incb: SizeInt; const c: PDouble; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA - b[i * incb];

end;

procedure vdsMulI(const N: SizeInt; const ALPHA: double; const b: PDouble;
  const incb: SizeInt; const c: PDouble; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA * b[i * incb];

end;

procedure vdsDivI(const N: SizeInt; const ALPHA: double; const b: PDouble;
  const incb: SizeInt; const c: PDouble; const incc: SizeInt); overload; inline;
var
  i: SizeInt;
begin

  for i := 0 to N - 1 do
    c[i * incc] := ALPHA / b[i * incb];

end;

procedure vsAddB(const N: SizeInt; const a: PSingle; const blockSize: SizeInt; const b: PSingle; const incb: SizeInt; const batch : SizeInt =1); overload; inline;
var
  i, j, k: SizeInt;
  c: PSingle;
  bb: single;
begin
  {$ifdef CPUX64}
  if AVX2Support then begin
    for k := 0 to batch - 1 do
      for i:=0 to N-1 do begin
        c := a + (k*N + i)*blockSize;
        bb := b[i*incb];
        vssAddI_avx(blockSize, bb, c, c);
      end;
    exit
  end;
  {$endif}
  for k := 0 to batch - 1 do
    for i := 0 to N - 1 do begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      vssAddI(blockSize, bb, c, 1, c, 1);
      //for j:=0 to blockSize-1 do
      //  c[j] := c[j] + bb
    end;
end;

procedure vsSubB(const N: SizeInt; const a: PSingle;
  const blockSize: SizeInt; const b: PSingle; const incb: SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PSingle;
  bb: single;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c :=  a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] - bb;
    end;
end;

procedure vsMulB(const N: SizeInt; const a: PSingle;
  const blockSize: SizeInt; const b: PSingle; const incb: SizeInt; const batch :SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PSingle;
  bb: single;
begin
  {$ifdef CPUX64}
  if AVX2Support then begin
    for k := 0 to batch - 1 do
      for i:=0 to N-1 do begin
        c := a + (k*N + i)*blockSize;
        bb := b[i*incb];
        vssMulI_avx(blockSize, bb, c, c);
      end;
    exit
  end;
  {$endif}
  for k := 0 to batch - 1 do
    for i := 0 to N - 1 do begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      vssMulI(blockSize, bb, c, 1, c, 1);
      //for j:=0 to blockSize-1 do
      //  c[j] := c[j] * bb
    end;
end;

procedure vsDivB(const N: SizeInt; const a: PSingle;
  const blockSize: SizeInt; const b: PSingle; const incb: SizeInt ; const batch : SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PSingle;
  bb: single;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] / bb;
    end;
end;

procedure vsMulAddB(const N: SizeInt; const a: PSingle;
  const blockSize: SizeInt; const b: PSingle; const incb: SizeInt; const c: PSingle; const incc: SizeInt; const batch :SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  t: PSingle;
  bb, cc: single;
begin
  {$ifdef CPUX64}
  if AVX2Support then begin
    for k := 0 to batch - 1 do
      for i:=0 to N-1 do begin
        t := a + (k*N + i)*blockSize;
        bb := b[i*incb];
        cc := c[i*incc];
        vssMulAddI_avx(blockSize, bb, cc, t, t);
      end;
    exit
  end;
  {$endif}
  for k := 0 to batch - 1 do
    for i := 0 to N - 1 do begin
      t := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      cc := c[i * incc];
      for j:=0 to blockSize-1 do
        t[j] := t[j] * bb + cc
    end;
end;

procedure vdAddB(const N: SizeInt; const a: PDouble;
  const blockSize: SizeInt; const b: PDouble; const incb: SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PDouble;
  bb: double;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] + bb;
    end;
end;

procedure vdSubB(const N: SizeInt; const a: PDouble;
  const blockSize: SizeInt; const b: PDouble; const incb: SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PDouble;
  bb: double;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] - bb;
    end;
end;

procedure vdMulB(const N: SizeInt; const a: PDouble;
  const blockSize: SizeInt; const b: PDouble; const incb: SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PDouble;
  bb: double;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] * bb;
    end;
end;

procedure vdDivB(const N: SizeInt; const a: PDouble;
  const blockSize: SizeInt; const b: PDouble; const incb: SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  c: PDouble;
  bb: double;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      c := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      for j := 0 to blockSize - 1 do
        c[j] := c[j] / bb;
    end;
end;

procedure vdMulAddB(const N: SizeInt; const a: PDouble;
  const blockSize: SizeInt; const b: PDouble; const incb: SizeInt; const c: PDouble; const incc:SizeInt; const batch:SizeInt = 1); overload; inline;
var
  i, j, k: SizeInt;
  t: PDouble;
  bb, cc: double;
begin
  for k:= 0 to batch -1 do
    for i := 0 to N - 1 do
    begin
      t := a + (k*N + i)*blockSize;
      bb := b[i * incb];
      cc := c[i * incc];
      for j := 0 to blockSize - 1 do
        t[j] := t[j] * bb + cc;
    end;
end;

{$if defined(CPUX64)}
procedure snormvss_avx(const N:SizeInt; const A:Psingle; const aMean,aStdDev:Single);assembler;
asm
  mov          rax      ,    N
  pxor         xmm0     ,    xmm0
  subss        xmm0     ,    aMean
  vbroadcastss ymm0     ,    xmm0
  rcpss        xmm1     ,    aStdDev
  vbroadcastss ymm1     ,    xmm1
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vaddps       ymm2     ,    ymm0,  yword [A]
  vmulps       ymm2     ,    ymm1,  ymm2
  vmovups      yword[A] ,    ymm2
  add          A        ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
  vzeroupper
@while2:
  vaddss       xmm2     ,    xmm0,  dword [A]
  vmulps       xmm2     ,    xmm1,  xmm2
  vmovss       dword[A] ,    xmm2
  add          A        ,    4
  dec          rax
  jnz         @while2
@done:

end;
{$endif}

procedure snormvss(const N: SizeInt; const src: PSingle; const aMean, aStdDev: single);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    src[i] := (src[i] - aMean) / aStdDev;
end;

procedure dnormvss(const N: SizeInt; const src: PDouble; const aMean, aStdDev: double);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    src[i] := (src[i] - aMean) / aStdDev;
end;

procedure _snormvv(const N: SizeInt; const mean: PSingle; const meanStride: SizeInt;
  const variance: PSingle; const varianceStride: SizeInt; const dst: PSingle;
  const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
  begin
    dst[i * dstStride] := (dst[i * dstStride] - mean[i * meanStride]) /
      sqrt(variance[i * varianceStride] + sEPSILON);
  end;
end;

procedure _dnormvv(const N: SizeInt; const mean: PDouble; const meanStride: SizeInt;
  const variance: PDouble; const varianceStride: SizeInt; const dst: PDouble;
  const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
  begin
    dst[i * dstStride] := (dst[i * dstStride] - mean[i * meanStride]) /
      sqrt(variance[i * varianceStride] + dEPSILON);
  end;
end;

procedure _snormblkvv(const N: SizeInt; const mean: PSingle;
  const meanStride: SizeInt; const variance: PSingle; const varianceStride: SizeInt;
  const dst: PSingle; const blockSize: SizeInt); overload; inline;
var
  i, j: SizeInt;
  d: single;
  o: PSingle;
begin
  {$if defined(CPUX64)}
  if AVX2Support then
    for i := 0 to N-1 do begin
        o := dst + i * blockSize;
        d := sqrt(math.max(variance[i*varianceStride] , sEPSILON));
        snormvss_avx(blockSize, o, mean[i*meanStride], d)
    end
  else
  {$endif}
  for i := 0 to N - 1 do
  begin
    o := dst + i * blockSize;
    d := sqrt(Math.max(variance[i * varianceStride], sEPSILON));
    snormvss(blockSize, o, mean[i * meanStride], d);
    //for j:=0 to blockSize-1 do
    //  o[j] := (o[j] - mean[i*meanStride]) / d
  end;
end;

procedure _dnormblkvv(const N: SizeInt; const mean: PDouble;
  const meanStride: SizeInt; const variance: PDouble; const varianceStride: SizeInt;
  const dst: PDouble; const blockSize: SizeInt); overload; inline;
var
  i, j: SizeInt;
  d: double;
  o: PDouble;
begin
  for i := 0 to N - 1 do
  begin
    o := dst + i * blockSize;
    d := sqrt(Math.max(variance[i * varianceStride], dEPSILON));
    dnormvss(blockSize, o, mean[i * meanStride], d);
    //for j:=0 to blockSize-1 do
    //  o[j] := (o[j] - mean[i*meanStride]) / d
  end;
end;

procedure matsDegrade(const matIn: PSingle; const matOut: PSingle;
  const rank: SizeInt; const row, col: SizeInt);
var
  c, r, cc, rr, L: integer;
begin
  L := rank - 1;
  for r := 0 to rank - 1 do
    for c := 0 to rank - 1 do
      if (c <> col) and (r <> row) then
      begin
        if c > col then cc := c - 1
        else
          cc := c;
        if r > row then rr := r - 1
        else
          rr := r;
        matOut[rr * L + cc] := matIn[r * rank + c];
      end;
end;

function matsDeterminant(const mat: PSingle; const rank: SizeInt): single;
var
  A: array[0..WORKSPACE_SIZE - 1] of single;
  det: single;
  i: SizeInt;
begin
  Result := 0;
  case rank of
    2: Result := mat[0] * mat[3] - mat[1] * mat[2];

    3: Result := mat[0] * (mat[4] * mat[8] - mat[5] * mat[7]) - mat[1] *
        (mat[3] * mat[8] - mat[5] * mat[6]) + mat[2] * (mat[3] * mat[7] - mat[4] * mat[6]);

    4: Result :=
        (mat[0] * mat[5] - mat[4] * mat[1]) * (mat[10] * mat[15] - mat[14] * mat[11]) -
        (mat[0] * mat[9] - mat[8] * mat[1]) * (mat[6] * mat[15] - mat[14] * mat[7]) +
        (mat[0] * mat[13] - mat[12] * mat[1]) * (mat[6] * mat[11] - mat[10] * mat[7]) +
        (mat[4] * mat[9] - mat[8] * mat[5]) * (mat[2] * mat[15] - mat[14] * mat[3]) -
        (mat[4] * mat[13] - mat[12] * mat[5]) * (mat[2] * mat[11] - mat[10] * mat[3]) +
        (mat[8] * mat[13] - mat[12] * mat[9]) * (mat[2] * mat[7] - mat[6] * mat[3]);
    else
    begin
      assert(rank * rank <= WORKSPACE_SIZE, '[Determinant] Matrix size is too big!');
      for i := 0 to rank - 1 do //if assigned(Data) then
      begin
        matsDegrade(mat, @A[0], rank, 0, i);
        det := matsDeterminant(@A[0], rank - 1);
        Result := Result + (1 - 2 * (i and 1)) * det * mat[i];
        //if i and 1=0 then
        //  result := result + det*mat[i]
        //else
        //  result := result - det*mat[i]
      end;
    end;
  end;
end;

procedure matsCofactors(const matIn: PSingle; const matOut: PSingle;
  const rank: SizeInt);
var
  A: array[0..WORKSPACE_SIZE - 1] of single;
  i, j: SizeInt;
begin
  for j := 0 to rank - 1 do
    for i := 0 to rank - 1 do
    begin
      matsDegrade(matIn, @A[0], rank, j, i);
      matOut[j * rank + i] := (1 - 2 * ((j + i) and 1)) * matsDeterminant(@A[0], rank - 1);
      //if boolean((j+i) and 1) then
      //  matOut[j*rank + i] := -matsDeterminant(@A[0], rank-1)
      //else
      //  matOut[j*rank + i] := matsDeterminant(@A[0], rank-1);
    end;
end;

procedure matsTranspose(const matIn: PSingle; const matOut: PSingle;
  const rows, cols: SizeInt);
var
  A: array[0..WORKSPACE_SIZE - 1] of single;
  r, c: SizeInt;
begin
  assert(rows * cols <= WORKSPACE_SIZE, '[Transpose] Matrix is too big!');
  for c := 0 to cols - 1 do
    for r := 0 to rows - 1 do
      A[c * rows + r] := matIn[r * cols + c];
  move(A[0], matOut[0], rows * cols * sizeOf(single));
end;

procedure matsInverse(const matIn: PSingle; const matOut: PSingle; const rank: SizeInt);
var
  det: single;
  i: SizeInt;
begin
  det := matsDeterminant(matIn, rank);
  Assert(det <> 0, 'Matrix inverse is not resolvable!');
  det := 1 / det;
  case rank of
    2: begin
      matOut[0] := matOut[3];
      matOut[1] := -matOut[1];
      matOut[2] := -matOut[2];
      matOut[3] := matOut[0];
      //result.Mul(det);
    end;
    3: begin
      matOut[0] := (matIn[4] * matIn[8] - matIn[5] * matIn[7]);
      matOut[3] := -(matIn[3] * matIn[8] - matIn[5] * matIn[6]);
      matOut[6] := (matIn[3] * matIn[7] - matIn[4] * matIn[6]);
      matOut[1] := -(matIn[1] * matIn[8] - matIn[2] * matIn[7]);
      matOut[4] := (matIn[0] * matIn[8] - matIn[2] * matIn[6]);
      matOut[7] := -(matIn[0] * matIn[7] - matIn[1] * matIn[6]);
      matOut[0] := (matIn[1] * matIn[5] - matIn[2] * matIn[4]);
      matOut[5] := -(matIn[0] * matIn[5] - matIn[2] * matIn[3]);
      matOut[8] := (matIn[0] * matIn[4] - matIn[1] * matIn[3]);
    end;
      //4:begin
      //  matOut[0 + 4*0] := matIn[1 + 4*1]*(matIn[2 + 4*2]*matIn[4 + 4*3]-matIn[2 + 4*3]*matIn[3 + 4*2]) + matIn[1 + 4*2]*(matIn[2 + 4*3]*matIn[3 + 4*1] - matIn[2 + 4*1]*matIn[3 + 4*3]) + matIn[1 + 4*3]*(matIn[2 +4*1]*matIn[3 + 4*2]-matIn[2 + 4*2]*matIn[3 + 4*1]);
      //  matOut[0 + 4*1] := matIn[2 + 4*1]*(matIn[0 + 4*2]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[3 + 4*2]) + matIn[2 + 4*2]*(matIn[0 + 4*3]*matIn[3 + 4*1] - matIn[0 + 4*1]*matIn[3 + 4*3]) + matIn[2 + 4*3]*(matIn[0 +4*1]*matIn[3 + 4*2]-matIn[0 + 4*2]*matIn[3 + 4*1]);
      //  matOut[0 + 4*2] := matIn[3 + 4*1]*(matIn[0 + 4*2]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[1 + 4*2]) + matIn[3 + 4*2]*(matIn[0 + 4*3]*matIn[1 + 4*1] - matIn[0 + 4*1]*matIn[1 + 4*3]) + matIn[3 + 4*3]*(matIn[0 +4*1]*matIn[1 + 4*2]-matIn[0 + 4*2]*matIn[1 + 4*1]);
      //  matOut[0 + 4*3] := matIn[0 + 4*1]*(matIn[1 + 4*3]*matIn[4 + 4*2]-matIn[1 + 4*2]*matIn[2 + 4*3]) + matIn[0 + 4*2]*(matIn[1 + 4*1]*matIn[2 + 4*3] - matIn[1 + 4*3]*matIn[2 + 4*1]) + matIn[0 + 4*3]*(matIn[1 +4*2]*matIn[2 + 4*1]-matIn[1 + 4*1]*matIn[2 + 4*2]);
      //  matOut[1 + 4*0] := matIn[1 + 4*2]*(matIn[2 + 4*0]*matIn[4 + 4*3]-matIn[2 + 4*3]*matIn[3 + 4*0]) + matIn[1 + 4*3]*(matIn[2 + 4*2]*matIn[3 + 4*0] - matIn[2 + 4*0]*matIn[3 + 4*2]) + matIn[1 + 4*0]*(matIn[2 +4*3]*matIn[3 + 4*2]-matIn[2 + 4*2]*matIn[3 + 4*3]);
      //  matOut[1 + 4*1] := matIn[2 + 4*2]*(matIn[0 + 4*0]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[3 + 4*0]) + matIn[2 + 4*3]*(matIn[0 + 4*2]*matIn[3 + 4*0] - matIn[0 + 4*0]*matIn[3 + 4*2]) + matIn[2 + 4*0]*(matIn[0 +4*3]*matIn[3 + 4*2]-matIn[0 + 4*2]*matIn[3 + 4*3]);
      //  matOut[1 + 4*2] := matIn[3 + 4*2]*(matIn[0 + 4*0]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[1 + 4*0]) + matIn[3 + 4*3]*(matIn[0 + 4*2]*matIn[1 + 4*0] - matIn[0 + 4*0]*matIn[1 + 4*2]) + matIn[3 + 4*0]*(matIn[0 +4*3]*matIn[1 + 4*2]-matIn[0 + 4*2]*matIn[1 + 4*3]);
      //  matOut[1 + 4*3] := matIn[0 + 4*2]*(matIn[1 + 4*3]*matIn[4 + 4*0]-matIn[1 + 4*0]*matIn[2 + 4*3]) + matIn[0 + 4*3]*(matIn[1 + 4*0]*matIn[2 + 4*2] - matIn[1 + 4*2]*matIn[2 + 4*0]) + matIn[0 + 4*0]*(matIn[1 +4*2]*matIn[2 + 4*3]-matIn[1 + 4*3]*matIn[2 + 4*2]);
      //  matOut[2 + 4*0] := matIn[1 + 4*3]*(matIn[2 + 4*0]*matIn[4 + 4*1]-matIn[2 + 4*1]*matIn[3 + 4*0]) + matIn[1 + 4*0]*(matIn[2 + 4*1]*matIn[3 + 4*3] - matIn[2 + 4*3]*matIn[3 + 4*1]) + matIn[1 + 4*1]*(matIn[2 +4*3]*matIn[3 + 4*0]-matIn[2 + 4*0]*matIn[3 + 4*3]);
      //  matOut[2 + 4*1] := matIn[2 + 4*3]*(matIn[0 + 4*0]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[3 + 4*0]) + matIn[2 + 4*0]*(matIn[0 + 4*1]*matIn[3 + 4*3] - matIn[0 + 4*3]*matIn[3 + 4*1]) + matIn[2 + 4*1]*(matIn[0 +4*3]*matIn[3 + 4*0]-matIn[0 + 4*0]*matIn[3 + 4*3]);
      //  matOut[2 + 4*2] := matIn[3 + 4*3]*(matIn[0 + 4*0]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[1 + 4*0]) + matIn[3 + 4*0]*(matIn[0 + 4*1]*matIn[1 + 4*3] - matIn[0 + 4*3]*matIn[1 + 4*1]) + matIn[3 + 4*1]*(matIn[0 +4*3]*matIn[1 + 4*0]-matIn[0 + 4*0]*matIn[1 + 4*3]);
      //  matOut[2 + 4*3] := matIn[0 + 4*3]*(matIn[1 + 4*1]*matIn[4 + 4*0]-matIn[1 + 4*0]*matIn[2 + 4*1]) + matIn[0 + 4*0]*(matIn[1 + 4*3]*matIn[2 + 4*1] - matIn[1 + 4*1]*matIn[2 + 4*3]) + matIn[0 + 4*1]*(matIn[1 +4*0]*matIn[2 + 4*3]-matIn[1 + 4*3]*matIn[2 + 4*0]);
      //  matOut[3 + 4*0] := matIn[1 + 4*0]*(matIn[2 + 4*2]*matIn[4 + 4*1]-matIn[2 + 4*1]*matIn[3 + 4*2]) + matIn[1 + 4*1]*(matIn[2 + 4*0]*matIn[3 + 4*2] - matIn[2 + 4*2]*matIn[3 + 4*0]) + matIn[1 + 4*2]*(matIn[2 +4*1]*matIn[3 + 4*0]-matIn[2 + 4*0]*matIn[3 + 4*1]);
      //  matOut[3 + 4*1] := matIn[2 + 4*0]*(matIn[0 + 4*2]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[3 + 4*2]) + matIn[2 + 4*1]*(matIn[0 + 4*0]*matIn[3 + 4*2] - matIn[0 + 4*2]*matIn[3 + 4*0]) + matIn[2 + 4*2]*(matIn[0 +4*1]*matIn[3 + 4*0]-matIn[0 + 4*0]*matIn[3 + 4*1]);
      //  matOut[3 + 4*2] := matIn[3 + 4*0]*(matIn[0 + 4*2]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[1 + 4*2]) + matIn[3 + 4*1]*(matIn[0 + 4*0]*matIn[1 + 4*2] - matIn[0 + 4*2]*matIn[1 + 4*0]) + matIn[3 + 4*2]*(matIn[0 +4*1]*matIn[1 + 4*0]-matIn[0 + 4*0]*matIn[1 + 4*1]);
      //  matOut[3 + 4*3] := matIn[0 + 4*0]*(matIn[1 + 4*1]*matIn[4 + 4*2]-matIn[1 + 4*2]*matIn[2 + 4*1]) + matIn[0 + 4*1]*(matIn[1 + 4*2]*matIn[2 + 4*0] - matIn[1 + 4*0]*matIn[2 + 4*2]) + matIn[0 + 4*2]*(matIn[1 +4*0]*matIn[2 + 4*1]-matIn[1 + 4*1]*matIn[2 + 4*0]);
      //end
    else
    begin
      matsCofactors(matIn, matOut, rank);
      matsTranspose(matOut, matOut, rank, rank);
    end
  end;
  //TT.Conj(@result.data[0],Length(result.Data),@result.data[0]);  // incase of a Complex Matrix
  cblas_sscal(rank * rank, det, matOut, 1);

end;

procedure matdDegrade(const matIn: PDouble; const matOut: PDouble;
  const rank: SizeInt; const row, col: SizeInt);
var
  c, r, cc, rr, L: SizeInt;
begin
  L := rank - 1;
  for r := 0 to rank - 1 do
    for c := 0 to rank - 1 do
      if (c <> col) and (r <> row) then
      begin
        if c > col then cc := c - 1
        else
          cc := c;
        if r > row then rr := r - 1
        else
          rr := r;
        matOut[rr * L + cc] := matIn[r * rank + c];
      end;
end;

function matdDeterminant(const mat: PDouble; const rank: SizeInt): double;
var
  A: array[0..WORKSPACE_SIZE - 1] of double;
  det: double;
  i: SizeInt;
begin
  Result := 0;
  case rank of
    2: Result := mat[0] * mat[3] - mat[1] * mat[2];

    3: Result := mat[0] * (mat[4] * mat[8] - mat[5] * mat[7]) - mat[1] *
        (mat[3] * mat[8] - mat[5] * mat[6]) + mat[2] * (mat[3] * mat[7] - mat[4] * mat[6]);

    4: Result :=
        (mat[0] * mat[5] - mat[4] * mat[1]) * (mat[10] * mat[15] - mat[14] * mat[11]) -
        (mat[0] * mat[9] - mat[8] * mat[1]) * (mat[6] * mat[15] - mat[14] * mat[7]) +
        (mat[0] * mat[13] - mat[12] * mat[1]) * (mat[6] * mat[11] - mat[10] * mat[7]) +
        (mat[4] * mat[9] - mat[8] * mat[5]) * (mat[2] * mat[15] - mat[14] * mat[3]) -
        (mat[4] * mat[13] - mat[12] * mat[5]) * (mat[2] * mat[11] - mat[10] * mat[3]) +
        (mat[8] * mat[13] - mat[12] * mat[9]) * (mat[2] * mat[7] - mat[6] * mat[3]);
    else
    begin
      assert(rank * rank <= WORKSPACE_SIZE, '[Determinant] Matrix size is too big!');
      for i := 0 to rank - 1 do //if assigned(Data) then
      begin
        matdDegrade(mat, @A[0], rank, 0, i);
        det := matdDeterminant(@A[0], rank - 1);
        Result := Result + (1 - 2 * (i and 1)) * det * mat[i];
        //if i and 1=0 then
        //  result := result + det*mat[i]
        //else
        //  result := result - det*mat[i]
      end;
    end;
  end;
end;

procedure matdCofactors(const matIn: PDouble; const matOut: PDouble;
  const rank: SizeInt);
var
  A: array[0..WORKSPACE_SIZE - 1] of double;
  i, j: SizeInt;
begin
  for j := 0 to rank - 1 do
    for i := 0 to rank - 1 do
    begin
      matdDegrade(matIn, @A[0], rank, j, i);
      matOut[j * rank + i] := (1 - 2 * ((j + i) and 1)) * matdDeterminant(@A[0], rank - 1);
      //if boolean((j+i) and 1) then
      //  matOut[j*rank + i] := -matdDeterminant(@A[0], rank-1)
      //else
      //  matOut[j*rank + i] := matdDeterminant(@A[0], rank-1);
    end;
end;

procedure matdTranspose(const matIn: PDouble; const matOut: PDouble;
  const rows, cols: SizeInt);
var
  A: array[0..WORKSPACE_SIZE - 1] of double;
  r, c: SizeInt;
begin
  assert(rows * cols <= WORKSPACE_SIZE, '[Transpose] Matrix is too big!');
  for c := 0 to cols - 1 do
    for r := 0 to rows - 1 do
      A[c * rows + r] := matIn[r * cols + c];
  move(A[0], matOut[0], rows * cols * sizeOf(double));
end;

procedure matdInverse(const matIn: PDouble; const matOut: PDouble; const rank: SizeInt);
var
  det: double;
  i: SizeInt;
begin
  det := matdDeterminant(matIn, rank);
  Assert(det <> 0, 'Matrix inverse is not resolvable!');
  det := 1 / det;
  case rank of
    2: begin
      matOut[0] := matOut[3];
      matOut[1] := -matOut[1];
      matOut[2] := -matOut[2];
      matOut[3] := matOut[0];
      //result.Mul(det);
    end;
    3: begin
      matOut[0] := (matIn[4] * matIn[8] - matIn[5] * matIn[7]);
      matOut[3] := -(matIn[3] * matIn[8] - matIn[5] * matIn[6]);
      matOut[6] := (matIn[3] * matIn[7] - matIn[4] * matIn[6]);
      matOut[1] := -(matIn[1] * matIn[8] - matIn[2] * matIn[7]);
      matOut[4] := (matIn[0] * matIn[8] - matIn[2] * matIn[6]);
      matOut[7] := -(matIn[0] * matIn[7] - matIn[1] * matIn[6]);
      matOut[0] := (matIn[1] * matIn[5] - matIn[2] * matIn[4]);
      matOut[5] := -(matIn[0] * matIn[5] - matIn[2] * matIn[3]);
      matOut[8] := (matIn[0] * matIn[4] - matIn[1] * matIn[3]);
    end;
      //4:begin
      //  matOut[0 + 4*0] := matIn[1 + 4*1]*(matIn[2 + 4*2]*matIn[4 + 4*3]-matIn[2 + 4*3]*matIn[3 + 4*2]) + matIn[1 + 4*2]*(matIn[2 + 4*3]*matIn[3 + 4*1] - matIn[2 + 4*1]*matIn[3 + 4*3]) + matIn[1 + 4*3]*(matIn[2 +4*1]*matIn[3 + 4*2]-matIn[2 + 4*2]*matIn[3 + 4*1]);
      //  matOut[0 + 4*1] := matIn[2 + 4*1]*(matIn[0 + 4*2]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[3 + 4*2]) + matIn[2 + 4*2]*(matIn[0 + 4*3]*matIn[3 + 4*1] - matIn[0 + 4*1]*matIn[3 + 4*3]) + matIn[2 + 4*3]*(matIn[0 +4*1]*matIn[3 + 4*2]-matIn[0 + 4*2]*matIn[3 + 4*1]);
      //  matOut[0 + 4*2] := matIn[3 + 4*1]*(matIn[0 + 4*2]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[1 + 4*2]) + matIn[3 + 4*2]*(matIn[0 + 4*3]*matIn[1 + 4*1] - matIn[0 + 4*1]*matIn[1 + 4*3]) + matIn[3 + 4*3]*(matIn[0 +4*1]*matIn[1 + 4*2]-matIn[0 + 4*2]*matIn[1 + 4*1]);
      //  matOut[0 + 4*3] := matIn[0 + 4*1]*(matIn[1 + 4*3]*matIn[4 + 4*2]-matIn[1 + 4*2]*matIn[2 + 4*3]) + matIn[0 + 4*2]*(matIn[1 + 4*1]*matIn[2 + 4*3] - matIn[1 + 4*3]*matIn[2 + 4*1]) + matIn[0 + 4*3]*(matIn[1 +4*2]*matIn[2 + 4*1]-matIn[1 + 4*1]*matIn[2 + 4*2]);
      //  matOut[1 + 4*0] := matIn[1 + 4*2]*(matIn[2 + 4*0]*matIn[4 + 4*3]-matIn[2 + 4*3]*matIn[3 + 4*0]) + matIn[1 + 4*3]*(matIn[2 + 4*2]*matIn[3 + 4*0] - matIn[2 + 4*0]*matIn[3 + 4*2]) + matIn[1 + 4*0]*(matIn[2 +4*3]*matIn[3 + 4*2]-matIn[2 + 4*2]*matIn[3 + 4*3]);
      //  matOut[1 + 4*1] := matIn[2 + 4*2]*(matIn[0 + 4*0]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[3 + 4*0]) + matIn[2 + 4*3]*(matIn[0 + 4*2]*matIn[3 + 4*0] - matIn[0 + 4*0]*matIn[3 + 4*2]) + matIn[2 + 4*0]*(matIn[0 +4*3]*matIn[3 + 4*2]-matIn[0 + 4*2]*matIn[3 + 4*3]);
      //  matOut[1 + 4*2] := matIn[3 + 4*2]*(matIn[0 + 4*0]*matIn[4 + 4*3]-matIn[0 + 4*3]*matIn[1 + 4*0]) + matIn[3 + 4*3]*(matIn[0 + 4*2]*matIn[1 + 4*0] - matIn[0 + 4*0]*matIn[1 + 4*2]) + matIn[3 + 4*0]*(matIn[0 +4*3]*matIn[1 + 4*2]-matIn[0 + 4*2]*matIn[1 + 4*3]);
      //  matOut[1 + 4*3] := matIn[0 + 4*2]*(matIn[1 + 4*3]*matIn[4 + 4*0]-matIn[1 + 4*0]*matIn[2 + 4*3]) + matIn[0 + 4*3]*(matIn[1 + 4*0]*matIn[2 + 4*2] - matIn[1 + 4*2]*matIn[2 + 4*0]) + matIn[0 + 4*0]*(matIn[1 +4*2]*matIn[2 + 4*3]-matIn[1 + 4*3]*matIn[2 + 4*2]);
      //  matOut[2 + 4*0] := matIn[1 + 4*3]*(matIn[2 + 4*0]*matIn[4 + 4*1]-matIn[2 + 4*1]*matIn[3 + 4*0]) + matIn[1 + 4*0]*(matIn[2 + 4*1]*matIn[3 + 4*3] - matIn[2 + 4*3]*matIn[3 + 4*1]) + matIn[1 + 4*1]*(matIn[2 +4*3]*matIn[3 + 4*0]-matIn[2 + 4*0]*matIn[3 + 4*3]);
      //  matOut[2 + 4*1] := matIn[2 + 4*3]*(matIn[0 + 4*0]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[3 + 4*0]) + matIn[2 + 4*0]*(matIn[0 + 4*1]*matIn[3 + 4*3] - matIn[0 + 4*3]*matIn[3 + 4*1]) + matIn[2 + 4*1]*(matIn[0 +4*3]*matIn[3 + 4*0]-matIn[0 + 4*0]*matIn[3 + 4*3]);
      //  matOut[2 + 4*2] := matIn[3 + 4*3]*(matIn[0 + 4*0]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[1 + 4*0]) + matIn[3 + 4*0]*(matIn[0 + 4*1]*matIn[1 + 4*3] - matIn[0 + 4*3]*matIn[1 + 4*1]) + matIn[3 + 4*1]*(matIn[0 +4*3]*matIn[1 + 4*0]-matIn[0 + 4*0]*matIn[1 + 4*3]);
      //  matOut[2 + 4*3] := matIn[0 + 4*3]*(matIn[1 + 4*1]*matIn[4 + 4*0]-matIn[1 + 4*0]*matIn[2 + 4*1]) + matIn[0 + 4*0]*(matIn[1 + 4*3]*matIn[2 + 4*1] - matIn[1 + 4*1]*matIn[2 + 4*3]) + matIn[0 + 4*1]*(matIn[1 +4*0]*matIn[2 + 4*3]-matIn[1 + 4*3]*matIn[2 + 4*0]);
      //  matOut[3 + 4*0] := matIn[1 + 4*0]*(matIn[2 + 4*2]*matIn[4 + 4*1]-matIn[2 + 4*1]*matIn[3 + 4*2]) + matIn[1 + 4*1]*(matIn[2 + 4*0]*matIn[3 + 4*2] - matIn[2 + 4*2]*matIn[3 + 4*0]) + matIn[1 + 4*2]*(matIn[2 +4*1]*matIn[3 + 4*0]-matIn[2 + 4*0]*matIn[3 + 4*1]);
      //  matOut[3 + 4*1] := matIn[2 + 4*0]*(matIn[0 + 4*2]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[3 + 4*2]) + matIn[2 + 4*1]*(matIn[0 + 4*0]*matIn[3 + 4*2] - matIn[0 + 4*2]*matIn[3 + 4*0]) + matIn[2 + 4*2]*(matIn[0 +4*1]*matIn[3 + 4*0]-matIn[0 + 4*0]*matIn[3 + 4*1]);
      //  matOut[3 + 4*2] := matIn[3 + 4*0]*(matIn[0 + 4*2]*matIn[4 + 4*1]-matIn[0 + 4*1]*matIn[1 + 4*2]) + matIn[3 + 4*1]*(matIn[0 + 4*0]*matIn[1 + 4*2] - matIn[0 + 4*2]*matIn[1 + 4*0]) + matIn[3 + 4*2]*(matIn[0 +4*1]*matIn[1 + 4*0]-matIn[0 + 4*0]*matIn[1 + 4*1]);
      //  matOut[3 + 4*3] := matIn[0 + 4*0]*(matIn[1 + 4*1]*matIn[4 + 4*2]-matIn[1 + 4*2]*matIn[2 + 4*1]) + matIn[0 + 4*1]*(matIn[1 + 4*2]*matIn[2 + 4*0] - matIn[1 + 4*0]*matIn[2 + 4*2]) + matIn[0 + 4*2]*(matIn[1 +4*0]*matIn[2 + 4*1]-matIn[1 + 4*1]*matIn[2 + 4*0]);
      //end
    else
    begin
      matdCofactors(matIn, matOut, rank);
      matdTranspose(matOut, matOut, rank, rank);
    end
  end;
  //TT.Conj(@result.data[0],Length(result.Data),@result.data[0]);  // incase of a Complex Matrix
  cblas_dscal(rank * rank, det, matOut, 1);

end;

class procedure TTensor<T>.cvtsb(const N: SizeInt; const src: PSingle; const dst: pbyte);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtsi8(const N: SizeInt; const src: PSingle;
  const dst: PShortInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtsi16(const N: SizeInt; const src: PSingle;
  const dst: PSmallInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtsi32(const N: SizeInt; const src: PSingle; const dst: PInt32);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtsd(const N: SizeInt; const src: PSingle; const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtss(const N: SizeInt; const src: PSingle; const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtdd(const N: SizeInt; const src: PDouble; const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtdb(const N: SizeInt; const src: PDouble; const dst: pbyte);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtdi8(const N: SizeInt; const src: PDouble;
  const dst: PShortInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtdi16(const N: SizeInt; const src: PDouble;
  const dst: PSmallInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtdi32(const N: SizeInt; const src: PDouble; const dst: PInt32);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := trunc(src[i]);
end;

class procedure TTensor<T>.cvtds(const N: SizeInt; const src: PDouble; const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtbi8(const N: SizeInt; const src: pbyte;
  const dst: PInt32);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtbi16(const N: SizeInt; const src: pbyte;
  const dst: PShortInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtbi32(const N: SizeInt; const src: pbyte;
  const dst: PSmallInt);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtbs(const N: SizeInt; const src: pbyte; const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvtbd(const N: SizeInt; const src: pbyte; const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti8s(const N: SizeInt; const src: PInt32;
  const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti8d(const N: SizeInt; const src: PInt32;
  const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti16s(const N: SizeInt; const src: PInt32;
  const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti16d(const N: SizeInt; const src: PInt32;
  const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti32s(const N: SizeInt; const src: PInt32;
  const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti32d(const N: SizeInt; const src: PInt32;
  const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti64s(const N: SizeInt; const src: PInt32;
  const dst: PSingle);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class procedure TTensor<T>.cvti64d(const N: SizeInt; const src: PInt32;
  const dst: PDouble);
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i] := src[i];
end;

class function TTensor<T>.sToStr(const v: single): string;
begin
  str(v: 1: sDigits, Result);
end;

class function TTensor<T>.dToStr(const v: double): string;
begin
  str(v: 1: sDigits, Result);
end;

class function TTensor<T>.i8ToStr(const v: shortint): string;
begin
  str(v: 1, Result);
end;

class function TTensor<T>.i16ToStr(const v: smallint): string;
begin
  str(v: 1, Result);
end;

class function TTensor<T>.i32ToStr(const v: int32): string;
begin
  str(v: 1, Result);
end;

class function TTensor<T>.i64ToStr(const v: int64): string;
begin
  str(v: 1, Result);
end;

class function TTensor<T>.bToStr(const v: byte): string;
begin
  str(v: 1, Result);
end;


procedure vsin(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := sin(src[i * srcStride]);
end;

procedure vcos(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := cos(src[i * srcStride]);
end;

procedure vtan(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := tan(src[i * srcStride]);
end;

procedure vcotan(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := cotan(src[i * srcStride]);
end;

procedure vtanH(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := tanH(src[i * srcStride]);
end;

procedure varcsin(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcSin(src[i * srcStride]);
end;

procedure varcCos(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcCos(src[i * srcStride]);
end;

procedure varcTan(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcTan(src[i * srcStride]);
end;

procedure varcTanH(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcTanH(src[i * srcStride]);
end;

procedure varcSinH(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcSinH(src[i * srcStride]);
end;

procedure varcCosH(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcCosH(src[i * srcStride]);
end;

procedure vlog10(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := Log10(src[i * srcStride]);
end;

procedure vlog2(const N: SizeInt; const src: PSingle; const srcStride: SizeInt;
  const dst: PSingle; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := log2(src[i * srcStride]);
end;

procedure vsin(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := sin(src[i * srcStride]);
end;

procedure vcos(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := cos(src[i * srcStride]);
end;

procedure vtan(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := tan(src[i * srcStride]);
end;

procedure vcotan(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := cotan(src[i * srcStride]);
end;

procedure vtanH(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := tanH(src[i * srcStride]);
end;

procedure varcsin(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcSin(src[i * srcStride]);
end;

procedure varcCos(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcCos(src[i * srcStride]);
end;

procedure varcTan(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcTan(src[i * srcStride]);
end;

procedure varcTanH(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcTanH(src[i * srcStride]);
end;

procedure varcSinH(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcSinH(src[i * srcStride]);
end;

procedure varcCosH(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := arcCosH(src[i * srcStride]);
end;

procedure vlog10(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := Log10(src[i * srcStride]);
end;

procedure vlog2(const N: SizeInt; const src: PDouble; const srcStride: SizeInt;
  const dst: PDouble; const dstStride: SizeInt); overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := log2(src[i * srcStride]);
end;

procedure vlog(const N: SizeInt; const a: single;
  const src: PSingle; const srcStride: SizeInt; const dst: PSingle; const dstStride: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := LogN(src[i * srcStride], a);
end;

procedure vlog(const N: SizeInt; const a: double;
  const src: Pdouble; const srcStride: SizeInt; const dst: Pdouble; const dstStride: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := LogN(src[i * srcStride], a);
end;

procedure vPow(const N: SizeInt; const a: single;
  const src: PSingle; const srcStride: SizeInt; const dst: PSingle; const dstStride: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := power(src[i * srcStride], a);
end;

procedure vPow(const N: SizeInt; const a: double;
  const src: Pdouble; const srcStride: SizeInt; const dst: Pdouble; const dstStride: SizeInt);
  overload; inline;
var
  i: SizeInt;
begin
  for i := 0 to N - 1 do
    dst[i * dstStride] := power(src[i * srcStride], a);
end;

{ TTensor }

function TTensor<T>.GetValue(idx: TSizes): T;
begin
  Result := Data[getIndex(idx)];
end;

procedure TTensor<T>.SetGroup(idx: SizeInt; AValue: TTensor<T>);
begin
  assert(AValue.Size() = groupSize(), '[SetGroup] wrong source tensor size.');
  move(AValue.Data[0], Data[idx * groupSize()], groupSize() * SizeOf(T));
end;

function TTensor<T>.GetDimensions: SizeInt;
begin
  Result := length(FShape);
end;

function TTensor<T>.GetGroup(idx: SizeInt): TTensor<T>;
var
  shp: TSizes;
begin
  shp := FShape;
  shp[0] := 1;
  Result.resize(shp);
  getGroup(idx, Result);
end;

procedure TTensor<T>.SetShape(AValue: TSizes);
begin
  if FShape = AValue then Exit;
  //FShape:=AValue;
  reShape(AValue);
end;

procedure TTensor<T>.SetStrides(AValue: TSizes);
begin
  if FStrides = AValue then Exit;
  FStrides := AValue;
end;

procedure TTensor<T>.SetValue(idx: TSizes; AValue: T);
begin
  Data[getIndex(idx)] := AValue;
end;

// unknown generic revert to their simple size math
class function TTensor<T>.__plus(const a, b: T): T;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: PShortInt(@Result)^ := PShortInt(@a)^ + PShortInt(@b)^;
        otSWord: PSmallInt(@Result)^ := PSmallInt(@a)^ + PSmallInt(@b)^;
        otSLong: PInt32(@Result)^ := PInt32(@a)^ + PInt32(@b)^;

      end;
    tkInt64: PInt64(@Result)^ := PInt64(@a)^ + PInt64(@b)^;
    tkFloat:
      case D.FloatType of
        ftSingle: PSingle(@Result)^ := PSingle(@a)^ + PSingle(@b)^;
        ftDouble: PDouble(@Result)^ := PDouble(@a)^ + PDouble(@b)^;
        ftCurr: PCurrency(@Result)^ := PCurrency(@a)^ + PCurrency(@b)^;
        //ftComp : PComp(@result)^ := PComp(@a)^ + PComp(@b)^;

      end;
  end;
end;

class function TTensor<T>.__minus(const a, b: T): T;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: PShortInt(@Result)^ := PShortInt(@a)^ - PShortInt(@b)^;
        otSWord: PSmallInt(@Result)^ := PSmallInt(@a)^ - PSmallInt(@b)^;
        otSLong: PInt32(@Result)^ := PInt32(@a)^ - PInt32(@b)^;

      end;
    tkInt64: PInt64(@Result)^ := PInt64(@a)^ - PInt64(@b)^;
    tkFloat:
      case D.FloatType of
        ftSingle: PSingle(@Result)^ := PSingle(@a)^ - PSingle(@b)^;
        ftDouble: PDouble(@Result)^ := PDouble(@a)^ - PDouble(@b)^;
        ftCurr: PCurrency(@Result)^ := PCurrency(@a)^ - PCurrency(@b)^;
        //ftComp : PComp(@result)^     := PComp(@a)^     - PComp(@b)^;

      end;
  end;
end;

class function TTensor<T>.__times(const a, b: T): T;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: PShortInt(@Result)^ := PShortInt(@a)^ * PShortInt(@b)^;
        otSWord: PSmallInt(@Result)^ := PSmallInt(@a)^ * PSmallInt(@b)^;
        otSLong: PInt32(@Result)^ := PInt32(@a)^ * PInt32(@b)^;
      end;

    tkInt64: PInt64(@Result)^ := PInt64(@a)^ * PInt64(@b)^;
    tkFloat:
      case D.FloatType of
        ftSingle: PSingle(@Result)^ := PSingle(@a)^ * PSingle(@b)^;
        ftDouble: PDouble(@Result)^ := PDouble(@a)^ * PDouble(@b)^;
        ftCurr: PCurrency(@Result)^ := PCurrency(@a)^ * PCurrency(@b)^;
        //ftComp : PComp(@result)^     := PComp(@a)^     * PComp(@b)^;
      end;
  end;
end;

class function TTensor<T>.__division(const a, b: T): T;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: PShortInt(@Result)^ := PShortInt(@a)^ div PShortInt(@b)^;
        otSWord: PSmallInt(@Result)^ := PSmallInt(@a)^ div PSmallInt(@b)^;
        otSLong: PInt32(@Result)^ := PInt32(@a)^ div PInt32(@b)^;
      end;

    tkInt64: PInt64(@Result)^ := PInt64(@a)^ div PInt64(@b)^;
    tkFloat:
      case D.FloatType of
        ftSingle: PSingle(@Result)^ := PSingle(@a)^ / PSingle(@b)^;
        ftDouble: PDouble(@Result)^ := PDouble(@a)^ / PDouble(@b)^;
        ftCurr: PCurrency(@Result)^ := PCurrency(@a)^ / PCurrency(@b)^;
        //ftComp : PComp(@result)^ := PComp(@a)^ {$if defined(FPC) and defined(MSWINDOWS)}/{$else}/{$endif} PComp(@b)^;
      end;
  end;
end;

class function TTensor<T>.__casti(const v: SizeInt): T;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: PShortInt(@Result)^ := PSizeInt(@v)^;
        otSWord: PSmallInt(@Result)^ := PSizeInt(@v)^;
        otSLong: PInt32(@Result)^ := PInt32(@v)^;
      end;
    tkInt64: PInt64(@Result)^ := PInt64(@v)^;
    tkFloat:
      case D.FloatType of
        ftSingle: PSingle(@Result)^ := PSizeInt(@v)^;
        ftDouble: PDouble(@Result)^ := PSizeInt(@v)^;
        ftCurr: PCurrency(@Result)^ := PSizeInt(@v)^;
        ftComp: PComp(@Result)^ := PSizeInt(@v)^;
      end;
  end;
end;

class function TTensor<T>.sPlus(const a, b: single): single;
begin
  Result := a + b;
end;

class function TTensor<T>.sminus(const a, b: single): single;
begin
  Result := a - b;
end;

class function TTensor<T>.sMul(const a, b: single): single;
begin
  Result := a * b;
end;

class function TTensor<T>.sDiv(const a, b: single): single;
begin
  Result := a / b;
end;

class function TTensor<T>.sCasti(const v: SizeInt): single;
begin
  Result := v;
end;

class function TTensor<T>.dPlus(const a, b: double): double;
begin
  Result := a + b;
end;

class function TTensor<T>.dminus(const a, b: double): double;
begin
  Result := a - b;
end;

class function TTensor<T>.dMul(const a, b: double): double;
begin
  Result := a * b;
end;

class function TTensor<T>.dDiv(const a, b: double): double;
begin
  Result := a / b;
end;

class function TTensor<T>.dCasti(const v: SizeInt): double;
begin
  Result := v;
end;

class function TTensor<T>.ubPlus(const a, b: byte): byte;
begin
  Result := a + b;
end;

class function TTensor<T>.ubminus(const a, b: byte): byte;
begin
  Result := a - b;
end;

class function TTensor<T>.ubMul(const a, b: byte): byte;
begin
  Result := a * b;
end;

class function TTensor<T>.ubDiv(const a, b: byte): byte;
begin
  Result := a div b;
end;

class function TTensor<T>.ubCasti(const v: SizeInt): byte;
begin
  Result := v;
end;

class function TTensor<T>.sbPlus(const a, b: shortint): shortint;
begin
  Result := a + b;
end;

class function TTensor<T>.sbMinus(const a, b: shortint): shortint;
begin
  Result := a - b;
end;

class function TTensor<T>.sbMul(const a, b: shortint): shortint;
begin
  Result := a * b;
end;

class function TTensor<T>.sbDiv(const a, b: shortint): shortint;
begin
  Result := a div b;
end;

class function TTensor<T>.sbCasti(const v: SizeInt): shortint;
begin
  Result := v;
end;

class function TTensor<T>.swPlus(const a, b: smallint): smallint;
begin
  Result := a + b;
end;

class function TTensor<T>.swMinus(const a, b: smallint): smallint;
begin
  Result := a - b;
end;

class function TTensor<T>.swMul(const a, b: smallint): smallint;
begin
  Result := a * b;
end;

class function TTensor<T>.swDiv(const a, b: smallint): smallint;
begin
  Result := a div b;
end;

class function TTensor<T>.swCasti(const v: SizeInt): smallint;
begin
  Result := v;
end;

class function TTensor<T>.slPlus(const a, b: longint): longint;
begin
  Result := a + b;
end;

class function TTensor<T>.slMinus(const a, b: longint): longint;
begin
  Result := a - b;
end;

class function TTensor<T>.slMul(const a, b: longint): longint;
begin
  Result := a * b;
end;

class function TTensor<T>.slDiv(const a, b: longint): longint;
begin
  Result := a div b;
end;

class function TTensor<T>.slCasti(const v: SizeInt): longint;
begin
  Result := v;
end;

class function TTensor<T>.sqPlus(const a, b: int64): int64;
begin
  Result := a + b;
end;

class function TTensor<T>.sqMinus(const a, b: int64): int64;
begin
  Result := a - b;
end;

class function TTensor<T>.sqMul(const a, b: int64): int64;
begin
  Result := a * b;
end;

class function TTensor<T>.sqDiv(const a, b: int64): int64;
begin
  Result := a div b;
end;

class function TTensor<T>.sqCasti(const v: SizeInt): int64;
begin
  Result := v;
end;

class function TTensor<T>._str(const v: T): string;
var
  P: PTypeInfo;
  D: PTypeData;
begin
  P := TypeInfo(T);
  D := getTypeData(P);
  case P.kind of
    tkInteger:
      case D.OrdType of
        otSByte: str(PShortInt(@v)^: 1, Result);
        otSWord: str(PSmallInt(@v)^: 1, Result);
        otSLong: str(PInt32(@v)^: 1, Result);
      end;
    tkInt64: str(PInt64(@v)^: 1, Result);
    tkFloat:
      case D.FloatType of
        ftSingle: str(PSingle(@v)^: 1: 3, Result);
        ftDouble: str(PDouble(@v)^: 1: 3, Result);
        ftCurr: str(PCurrency(@v)^: 1: 3, Result);
        ftComp: str(PComp(@v)^: 1, Result);
      end;
  end;
end;

class function TTensor<T>._compare(const a, b: T): SizeInt;
begin
  Result := TComparer<T>.Default.compare(a, b);
end;

class procedure TTensor<T>._conv2d(const src: PT; ker: PT; var dest: PT;
  const wSrc, hSrc, wKernel, hKernel, wPad, hPad, xStr, yStr, xDil, yDil: SizeInt);
var
  {kx, kw, }ky {,kh}, wp, hp, wDst, hDst, i, j: SizeInt;
  ker2, srcIM, dstIM: PT;
  acc: T;
begin
  if not assigned(dotvv) then dotvv := TTensor<T>.dot;
  //kw := wKernel div 2;
  //kh := hKernel div 2;
  //kSize := wKernel * hKernel;
  wDst := wSrc div xStr + wPad * 2 - wKernel + 1;
  hDst := hSrc div yStr + hPad * 2 - hKernel + 1;
  wP := {kw} -wPad;
  hP := {kh} -hPad;
  ker := ker {+ kh*wKernel}{ + kw};
  for i := hPad to hDst - hPad - 1 do
  begin
    dstIM := dest + i * wDst;
    for j := wPad to wDst - wPad - 1 do
    begin
      acc := dstIM[j];
      for ky := 0{-kh} to hKernel - 1{kh} do
      begin
        srcIM := src + (i * yStr + ky * yDil) * wSrc + j * xStr + hP * wSrc + wp;
        ker2 := ker + ky * wKernel;
        acc := plus(acc, dotvv(wKernel, ker2, 1, srcIm, xDil));
        //for kx := 0{-kw} to wKernel-1{kw} do
        //  acc :=  plus(acc , ker2[kx]*srcIM[kx*xDil]);
      end;
      dstIM[j] := acc;
    end;
  end;
end;

class procedure TTensor<T>.polynomial(const N: SizeInt; const coef: TArray<T>;
  dst: PT; const aStdDev: T);
var
  i, deg: SizeInt;
  val: T;
begin
  //Horner's Method https://en.wikipedia.org/wiki/Horner%27s_method
  deg := high(coef);

  for i := 0 to N - 1 do
  begin
    val := xLinear(0, deg, casti(i), coef);

    if compare(aStdDev, zero) > 0 then
      dst[i] := randg(val, aStdDev)
    else
      dst[i] := val;
  end;
end;

class function TTensor<T>.xLinear(const n, deg: SizeInt; const x: T;
  const coef: TArray<T>): T;
begin
  if n < deg then
    Result := plus(coef[n], Times(x, xLinear(n + 1, deg, x, coef)))
  else
    Result := coef[n];
end;

class function TTensor<T>.deCompose(var qr: PT; const m, n, rwidthq: SizeInt; var alpha: PT; var pivot: PSizeInt): integer;
var
  i, j, jbar, k, ii: SizeInt;
  beta, sigma, alphak, qrkk, s: T;
  y, sum: TArray<T>;
begin
  if not assigned(sumsqrv) then sumsqrv := TTensor<T>.sumsqr;
  Result := 1;
  setLength(y, n);
  setLength(sum, n);
  for j := 0 to n - 1 do
  begin
    //s := 0;
    //for i:=0 To m-1 Do
    //  s := plus(s, sqr(qr[i*rwidthq+j]));
    sum[j] := sumsqrv(m, qr + j, rwidthq);
    pivot[j] := j;
  end; {j}
  for k := 0 to n - 1 do
  begin
    sigma := sum[k];
    jbar := k;
    for j := k to n - 1 do
      if compare(sigma, sum[j]) < 0 then
      begin
        sigma := sum[j];
        jbar := j;
      end;
    if jbar <> k then
    begin
      i := pivot[k];
      pivot[k] := pivot[jbar];
      pivot[jbar] := i;
      sum[jbar] := sum[k];
      sum[k] := sigma;
      for i := 0 to m - 1 do
      begin
        ii := i * rwidthq;
        sigma := qr[ii + k];
        qr[ii + k] := qr[ii + jbar];
        qr[ii + jbar] := sigma;
      end; {i}
    end; {column interchange}
    //sigma := zero;
    //for i:=k to m-1 do
    //  sigma := plus(sigma, sqr(qr[i*rwidthq+k]));
    sigma := sumsqrv(m - k, qr + k * (rwidthq + 1), rwidthq);
    if compare(sigma, zero) = 0 then
    begin
      Result := 2;
      exit;
    end;
    qrkk := qr[k * rwidthq + k];
    if compare(qrkk, zero) < 0 then
      alphak := sqrt(sigma)
    else
      alphak := minus(zero, sqrt(sigma));
    alpha[k] := alphak;
    beta := division(one, minus(sigma, times(qrkk, alphak)));
    qr[k * rwidthq + k] := minus(qrkk, alphak);
    for j := k + 1 to n - 1 do
    begin
      s := zero;
      for i := k to m - 1 do
      begin
        ii := i * rwidthq;
        s := plus(s, times(qr[ii + k], qr[ii + j]));
      end; {i}
      y[j] := times(beta, s);
    end; {j}
    for j := k + 1 to n - 1 do
    begin
      for i := k to m - 1 do
      begin
        ii := i * rwidthq;
        qr[ii + j] := minus(qr[ii + j], times(qr[ii + k], y[j]));
      end; {i}
      sum[j] := minus(sum[j], sqr(qr[k * rwidthq + j]));
    end; {j}
  end; {k}
end; {decomp}

class procedure TTensor<T>.solve(const qr: TArray<T>; const M, N, rwidthq: SizeInt; var alpha: TArray<T>; var pivot: TArray<SizeInt>; var r, y: TArray<T>);
var
  i, j, ii: SizeInt;
  gamma, s: T;
  z: TArray<T>;
begin
  setLength(z, n);
  for j := 0 to n - 1 do
  begin
    gamma := zero;
    for i := j to m - 1 do
      gamma := plus(gamma, times(qr[i * rwidthq + j], r[i]));
    gamma := division(gamma, times(alpha[j], qr[j * rwidthq + j]));
    for i := j to m - 1 do
      r[i] := plus(r[i], times(gamma, qr[i * rwidthq + j]));
  end; {j}
  z[n - 1] := division(r[n - 1], alpha[n - 1]);
  for i := n - 2 downto 0 do
  begin
    s := r[i];
    ii := i * rwidthq;
    for j := i + 1 to n - 1 do
      s := minus(s, times(qr[ii + j], z[j]));
    z[i] := division(s, alpha[i]);
  end; {i}
  for i := 0 to n - 1 do
    y[pivot[i]] := z[i];
end; {solve}

class function TTensor<T>.SolveLeastSquares(const a: PT; const M, N, rwidtha: SizeInt; const b: PT; var x: PT): integer;
var
  i, j, ii: SizeInt;
  normy0, norme1, s: T;
  pa, pb, px: PT;
  qr, alpha, e, y, r: TArray<T>;
  pivot: TArray<SizeInt>;
  dnorme1, dnormy0: double;
begin
  if not assigned(sumsqrv) then sumsqrv := TTensor<T>.sumsqr;
  if (n < 1) or (m < n) then
    exit(3);
  pa := pointer(a);
  pb := pointer(b);
  px := pointer(x);
  setLength(qr, M*N);
  setLength(alpha, n);
  setLength(e, n);
  setLength(y, n);
  setLength(r, m);
  setLength(pivot, n);
  for i := 0 to m - 1 do
    move(pa[i * rwidtha], qr[i * n], n * sizeof(T));
  Result := decompose(PT(qr), m, n, n, PT(alpha), PSizeInt(pivot));
  if Result = 2 then
    exit;
  move(pb[0], r[0], m * SizeOf(T));
  solve(qr, m, n, n, alpha, pivot, r, y);
  for i := 0 to m - 1 do
  begin
    s := pb[i];
    ii := i * rwidtha;
    for j := 0 to n - 1 do
      s := minus(s, times(pa[ii + j], y[j]));
    r[i] := s;
  end; {i}
  solve(qr, m, n, n, alpha, pivot, r, e);
  //normy0 := zero;
  //norme1 := zero;
  //for i:=0 to n-1 do
  //  begin
  //    normy0 := plus(normy0, sqr(y[i]));
  //    norme1 := plus(norme1, sqr(e[i]))
  //  end; {i}
  normy0 := sumsqrv(n, pointer(y), 1);
  norme1 := sumsqrv(n, pointer(e), 1);

  vcvtd(1, @norme1, @dnorme1);
  vcvtd(1, @normy0, @dnormy0);
  if dnorme1 > 0.0625 * dnormy0 then
    exit(2);
  move(y[0], x[0], n * SizeOf(T));
end;

class function TTensor<T>.FitPloynomial(const M: SizeInt; degree: SizeInt; const x, y: PT; var b: PT): integer;
var
  i, j: SizeInt;
  fsum, fpn, ppn, ppn1, xppn1, p, alphaj, betaj: T;
  a, alpha, beta, pn, pn1: TArray<T>;
begin
  if (degree < 0) or (m < 1) then
  begin
    exit(3);
  end;
  Result := 1;
  if not assigned(sumv) then sumv := TTensor<T>.sum;
  if degree = 0 then begin
    fsum := sumv(m, y, 1);
    b[0] := division(fsum, casti(m));
  end else begin
    if degree > m - 1 then begin
      fillchar(b[m], (degree - m + 1) * sizeof(T), 0);
      degree := m - 1;
    end;
    setLength(alpha, degree);
    setLength(beta, degree);
    setLength(a, (degree + 1));
    setLength(pn, m);
    setLength(pn1, m);

    xppn1 := zero;
    ppn1 := casti(m);
    for i := 0 to m - 1 do begin
      pn[i] := zero;
      pn1[i] := one;
      xppn1 := plus(xppn1 , x[i]);
    end;
    alpha[0] := division(xppn1, ppn1);
    beta[0] := zero;
    for j := 1 to degree - 1 do begin
      alphaj := alpha[j - 1];
      betaj := beta[j - 1];
      ppn := ppn1;
      ppn1 := zero;
      xppn1 := zero;
      for i := 0 to m - 1 do begin
        p := minus(times(minus(x[i] , alphaj) , pn1[i]) , times(betaj , pn[i]));
        pn[i] := pn1[i];
        pn1[i] := p;
        p := sqr(p);
        ppn1 := plus(ppn1 , p);
        xppn1 := plus(xppn1 , times(x[i] , p));
      end;
      alpha[j] := division(xppn1, ppn1);
      beta[j] := division(ppn1, ppn);
    end;

    fpn := zero;
    for i := 0 to m - 1 do begin
      pn[i] := zero;
      pn1[i] := one;
      fpn := plus(fpn , y[i]);
    end;
    a[0] := division(fpn, casti(m));
    for j := 0 to degree - 1 do begin
      fpn := zero;
      ppn := zero;
      alphaj := alpha[j];
      betaj := beta[j];
      for i := 0 to m - 1 do begin
        p := minus(times(minus(x[i] , alphaj) , pn1[i]) , times(betaj , pn[i]));
        pn[i] := pn1[i];
        pn1[i] := p;
        fpn := plus(fpn , times(y[i] , p));
        ppn := plus(ppn , times(p , p));
      end;
      a[j + 1] := division(fpn, ppn);
    end;

    move(a[0], b[0], (degree + 1) * sizeof(T));
    for i := 0 to degree - 1 do
      for j := degree - i - 1 downto 0 do begin
        b[j + i] := minus(b[j + i] , times(alpha[j] , b[j + i + 1]));
        if j + i <> degree - 1 then
          b[j + i] := minus(b[j + i] , times( beta[j + 1] , b[j + i + 2]));
      end;
  end;
end;

constructor TTensor<T>.Create(const newShape: TSizes; aGroups: SizeInt;
  ASteps: SizeInt);
var
  sz: SizeInt;
begin
  //sz:=product(newShape)*Sizeof(T);
  //Self.Data:=AllocMem(sz);
  sz := product(newShape);
  if sz = 0 then exit;
  groups := 0;
  reshape(newShape, aGroups, aSteps);
  setLength(DynData, sz);
  Data := Pointer(DynData);

  {$if defined(USE_OPENCL)}
  //if computingDevice = cdOpenCL then
    devData := ocl.createDeviceBuffer(sz * sizeOf(T), TCLMemAccess.maReadWrite, nil);
  {$endif}
end;

procedure TTensor<T>.Free;
var
  d: PT;
begin
  {$ifdef USE_OPENCL}
  if assigned(devData) then begin
    ocl.freeDeviceBuffer(devData);
    devData := nil
  end;
  {$endif}
  FShape := nil;
  FDimSizes := nil;
  FStrides := nil;
  Data := nil;
  if length(DynData)>0 then
  begin
    groups := 0;
    steps := 0;
    //setLength(DynData, 0);
    DynData := nil;
    exit;
  end;
  if not Assigned(Data) then exit;
  d := Data;
  Data := nil;
  Freemem(d);
end;

function TTensor<T>.wasGPU(): boolean;
begin
  Result := lastOP <> cdCPU;
end;


{$if defined(USE_OPENCL)}

{$ASSERTIONS ON}
procedure initOpenCL(const platformId :SizeInt; const deviceId: SizeInt);
begin
    if not assigned(ocl) then begin
      ocl:= TNNOpenCL.Create(TCLDeviceType.dtALL);
      ocl.LoadFromFile(GetCurrentDir + '/../../../../NN/source/cl_sgemm.c' );
    end;
    ocl.ActivePlatformId := platformId;
    ocl.ActiveDeviceId := deviceId;
    if not ocl.isBuilt then ocl.build;
end;

procedure TTensor<T>.setOCL;
begin
  lastOP := cdOpenCL;
end;

procedure TTensor<T>.setCPU;
begin
  lastOp := cdCPU;
end;
{$endif}

procedure TTensor<T>.pushToDevice;
var
  sz: SizeInt;
begin
  {$if defined(USE_OPENCL)}
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opHostToDevice);
  {$endif}
  sz := byteSize();
  ocl.writeBuffer(devData, sz, Data);
  //ocl.finish();
  lastOP := cdOpenCL;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opHostToDevice);
  {$endif}
  {$endif}
end;

procedure TTensor<T>.pullFromDevice;
var
  sz: SizeInt;
begin
  {$if defined(USE_OPENCL)}
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opDeviceToHost);
  {$endif}
  sz := byteSize();
  ocl.readBuffer(devData, sz, Data);
  //ocl.finish();
  lastOP := cdCPU;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opDeviceToHost);
  {$endif}
  {$endif}
end;

procedure TTensor<T>.pullFromDevice(var dst: TTensor<T>);
var
  sz: SizeInt;
begin
  {$if defined(USE_OPENCL)}
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opDeviceToHost);
  {$endif}
  sz := byteSize();
  if not assigned(dst.Data) then
    dst.resize(FShape, groups);
  ocl.ReadBuffer(devData, sz, dst.Data);ocl.CheckError();
  //ocl.finish();
  dst.lastOP := cdCPU;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opDeviceToHost);
  {$endif}
  {$endif}
end;

procedure TTensor<T>.resetReference;
begin
  Data := pointer(DynData)
end;

//procedure TTensor<T>.convertTo<C>(var Trnsor: TTensor<C>);
//begin

//end;

procedure TTensor<T>.Fill(const val: T; const interval: T; const stride: SizeInt;
  start: SizeInt; Count: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opIncFill);
  {$endif}

  assert(stride > 0);
  i := 0;
  if (Count < 0) or (Count + start > Size()) then Count := Size() - start;
  if compare(Interval, Default(T)) = 0 then
    for i := 0 to Count div stride - 1 do Data[start + i * stride] := val
  else
    while i < Count do
    begin
      Data[start + i] := Plus(val, Times(CastI(i), interval));
      Inc(i, stride);
    end;
  {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opIncFill);
  {$endif}
end;

procedure TTensor<T>.Fill(const val: T);
var
  i: SizeInt;
begin
  FillExt(val, 0, Size())
end;

procedure TTensor<T>.FillExt(const val: T; const offset: SizeInt; const N: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opFill);
  {$endif}
  case sizeOf(T) of
    1: FillChar(Data[0], N, PAnsiChar(@val)^);
    2: FillWord(Data[0], N, PWord(@val)^);
    4: FillDWord(Data[0], N, PDWord(@val)^);
    8: FillQWord(Data[0], N, PQWord(@val)^);
    else
       for i := 0 to N - 1 do
         Data[i] := val
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opFill);
  {$endif}
end;

procedure TTensor<T>.Sort(dst: TTensor<T>; const Descending : boolean = false);
begin
  copyTo(dst);
  dst.Sort(Descending)
end;

procedure TTensor<T>.Sort(const Descending : boolean = false);
var i, N:SizeInt;
begin
  N := groupSize;
  for i:= 0 to groups-1 do
    TTools<T>.QuickSort(Data, i*N, (1+i)*N-1, compare, Descending);
end;

procedure TTensor<T>.linSpace(const start: T; const Finish: T; const N: SizeInt);
var
  i: SizeInt;
  interval: T;
begin
  if N > 0 then reSize([N]);
  interval := Division(Minus(finish, start), CastI(size() - 1));
  for i := 0 to Size() - 1 do
    Data[i] := Plus(start, Times(interval, CastI(i)));
end;

procedure TTensor<T>.UniformDistribution(const minVal, maxVal: T);
var
  r: T;
  i: SizeInt;
begin
  assert(assigned(rand), 'UniformDistribution : Operation not implemented');
  _mutex.Enter;
  r := Minus(maxVal, minVal);
  for i := 0 to Size() - 1 do
    Data[i] := plus(minVal, rand(r));
  _mutex.Leave;
end;

procedure TTensor<T>.NormalDistribution(const aMean, aStdDev: T);
var
  i: SizeInt;
begin
  assert(assigned(randG), 'NormalDistribution : Operation not implemented');
  _mutex.Enter;
  for i := 0 to Size() - 1 do
    Data[i] := Self.randG(aMean, aStdDev);
  _mutex.Leave;
end;

function TTensor<T>.sample(const n: SizeInt): SizeInt;
var
  _sum, r: T;
  i: SizeInt;
begin
  //float sum = sum_array(a, n);
  _sum  := sum();
  multiply(division(One , _sum));
  r := rand(one);
  for i := 0 to Size()-1 do begin
      r := r - data[i];
      if r <= 0 then exit(i);
  end;
  result := n - 1

end;

function TTensor<T>.findNaNs: TArray<SizeInt>;
var i, j:SizeInt;
begin
  assert(assigned(checkNan),'[findNaNs] : not implemented!');
  setLength(result, Size());
  j := 0;
  for i:= 0 to Size()-1 do
    if checkNan(data[i]) then begin
      result[j]:=i;
      inc(j)
    end;
  setLength(result, j)
end;

function TTensor<T>.findInfinities: TArray<SizeInt>;
var i, j:SizeInt;
begin
  assert(assigned(checkNan),'[findInfinities] : not implemented!');
  setLength(result, Size());
  j := 0;
  for i:= 0 to Size()-1 do
    if checkInf(data[i]) then begin
      result[j]:=i;
      inc(j)
    end;
  setLength(result, j)
end;

procedure TTensor<T>.setAll(const val: T; const stride: SizeInt);
var
  i: SizeInt;
begin
  for i := 0 to (Size() div stride) - 1 do
    Data[i * stride] := val;
end;

procedure TTensor<T>.reShape(const newShape: TSizes; const batch: SizeInt;
  const aSteps: SizeInt);
var
  i, Dim: SizeInt;
begin
  Assert((Length(newShape) > 0) and (batch >=0) and (aSteps>=0));
  if aSteps>0 then
    assert((length(newShape)>2) and (aSteps = newShape[0]) and (batch = newShape[1]))
  else
    if batch>0 then assert((length(newShape)>1) and (batch = newShape[0]));


  Dim := Length(FShape);
  FShape := copy(newShape);
  setLength(FStrides, Length(FShape));

  for i := Dim to high(FStrides) do
    FStrides[i] := 1;
  if Length(FShape) = 1 then
    setLength(FDimSizes, 0);

  if batch <> 0 then
    Groups := batch;
  if aSteps<>0 then
    Steps := aSteps;

  if Groups = 0 then
    Groups := 1;
  if Steps = 0 then
    Steps := 1;
  if length(FShape) < 2 then exit;
  setLength(FDimSizes, High(FShape));
  dim := FShape[High(FShape)];
  FDimSizes[High(FDimSizes)] := dim;
  for i := high(FShape) - 1 downto 1 do
  begin
    dim := dim * FShape[i];
    FDimSizes[i - 1] := dim;
  end;

end;

function TTensor<T>.reSize(const newShape: TSizes; const batch: SizeInt;
  const aSteps: SizeInt): TTensor<T>;
var
  SO, SN: SizeInt;
begin
  SO := Size();
  reshape(newShape, batch, aSteps);
  //data :=nil;
  //dynData:=nil;
  SN := product(newShape);
  if SO = SN then exit;
  setLength(DynData, SN);
  Data := pointer(DynData);
  {$if defined(USE_OPENCL)}
  //if computingDevice = cdOpenCL then
  begin
    if assigned(devData) then ocl.freeDeviceBuffer(devData);
    devData := ocl.createDeviceBuffer(SN * SizeOf(T));
  end;
  {$endif}

  Result := self;
end;

function TTensor<T>.Equal(const tensor: TTensor<T>): boolean;
var
  i: SizeInt;
begin
  Result := Length(FShape) = Length(tensor.Shape);
  Result := Result and (CompareMem(@FShape[0], @tensor.Shape[0],
    length(FShape) * sizeof(SizeInt)));
  if not Result then exit;
  for i := 0 to Size - 1 do
  begin
    Result := Result and (compare(Data[i], tensor.Data[i]) = 0);
    if not Result then exit;
  end;
end;

procedure TTensor<T>.replace(const what, aReplace: T);
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  for i := 0 to Size() - 1 do
    if compare(Data[i], what) = 0 then
      Data[i] := aReplace;
end;

procedure TTensor<T>.find(const what: T; var indecies: TArray<SizeInt>);
var
  i, p: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  if not assigned(indecies) then setLength(indecies, Size);
  p := 0;
  for i := 0 to Size() - 1 do
    if compare(Data[i], what) = 0 then
    begin
      indecies[p] := i;
      Inc(p);
    end;
  setLength(indecies, p);
end;

function TTensor<T>.indexOf(const val: T): SizeInt;
var
  i: SizeInt;
begin
  for i := 0 to Size() - 1 do
    if compare(val, Data[i]) = 0 then
      exit(i);
  Result := -1;
end;

function TTensor<T>.Permute(const newArrange: TSizes; dstTensor: Pointer): TTensor<T>;
var
  j, y, x: SizeInt;
  newShape, newIndecies, indecies: TSizes;
  dst: ^TTensor<T> absolute dstTensor;
begin
  setLength(newShape, length(newArrange));
  setLength(newIndecies, length(newArrange));
  setLength(indecies, length(newArrange));

  for j := 0 to High(newArrange) do
    newShape[newArrange[j]] := FShape[j];

  if not assigned(dst) then
  begin
    Result := TTensor<T>.Create(newShape);
    dst := @Result;
  end
  else
  begin
    dst.reShape(newShape);
  end;
  permute(dst^, Self, newShape, Indecies, newIndecies, newArrange, 0);
  dst^.assignTo(Result);
end;

procedure TTensor<T>.CopyTo(const dst: TTensor<T>; const dstOffset: SizeInt;
  const dstStride: SizeInt; const srcOffset: SizeInt; const srcStride: SizeInt;
  N: SizeInt);
var
  i: SizeInt;
  d, s: PT;
begin
  if N = 0 then N := Size() div srcStride;
{$if defined(_USE_OPENCL)}
  if wasGPU then begin
    ocl.FErr := longint(CLBlastScopy(N, devData, srcOffset, srcStride, dst.devData, dstOffset, dstStride, @ocl.ActiveQueue, nil));ocl.CheckError();
    exit
  end;
{$endif}
  if (dstStride = 1) and (srcStride = 1) then
  begin
    move((Data + srcOffset)^, (dst.data + dstOffset)^, N * sizeOf(T));
    exit;
  end;

  d := dst.Data + dstOffset;
  s := Data + srcOffset;
  for i := 0 to N - 1 do
    d[i * dstStride] := s[i * srcStride];
end;

procedure TTensor<T>.ShallowCopy(const Source: TTensor<T>);
begin

  DynData := Source.DynData;
  Data := pointer(DynData);
end;

procedure TTensor<T>.ShallowCopy(const Source: TArray<T>; const AShape: TArray<SizeInt>);
begin
  if assigned(AShape) then
    reshape(AShape)
  else if not assigned(FShape) then
    reshape([length(Source)]);
  DynData := Source;
  Data := pointer(DynData);
end;

function TTensor<T>.getIndex(const idx: TSizes): SizeInt;
var
  i: SizeInt;
begin
  Assert(length(FShape) = Length(Idx),
    '[getIndex]: idx and Tensor shape must be identical.');
  Result := 0;
  for i := 0 to high(FDimSizes) do
    Inc(Result, idx[i] * FDimSizes[i]);
  Inc(Result, idx[high(idx)]);
end;

function TTensor<T>.Size(): SizeInt;
var
  i: SizeInt;
begin
  Result := product(FShape);
end;

function TTensor<T>.groupSize: SizeInt;
begin
  Result := Size() div groups;
end;

function TTensor<T>.byteSize(): SizeInt;
begin
  Result := Sizeof(T) * Size();
end;

function TTensor<T>.as2dWidth(): SizeInt;
begin
  result := FShape[high(FShape)];
end;

function TTensor<T>.as2dHeight(): sizeInt;
begin
  if Dimensions = 1 then exit(1);
  result := self.product(Dimensions - 1, pointer(FShape));
end;

procedure TTensor<T>.Squeeze(dim: SizeInt);
var
  i: SizeInt;
begin
  if dim > High(FShape) then exit;
  i := 0;
  if dim < 0 then
    while i < Length(FShape) do
      if FShape[i] = 1 then
        Delete(FShape, i, 1)
      else
        Inc(i)
  else
  if FShape[dim] = 1 then
    Delete(FShape, dim, 1);
end;

procedure TTensor<T>.UnSqueeze(newDim: TSizes);
var
  i, N: SizeInt;
begin
  if not assigned(newDim) then newDim := [0];
  N := Size();
  for i := high(newDim) downto 0 do
    if newDim[i] < N then
      insert(1, FShape, newDim[i]);
  //Insert(newDim, FShape,0);
  //reAllocMem(Data, Size()*SizeOf(T));
end;

function TTensor<T>.toString: string;
var
  indecies: TSizes;
begin
  Result := 'Empty Tensor []';
  if not Assigned(FShape) or not Assigned(Data) then exit();
  setLength(Indecies, length(FShape));
  Result := subPrint(Self, Indecies, 0);
end;

procedure TTensor<T>.fromString(const src: string; const separator: string);
begin
  //todo fromString
end;

function TTensor<T>.loadFromFile(var F: file; blockSize: SizeInt): SizeInt;
var
  r: integer;
begin
  if blockSize = 0 then blockSize := byteSize();
  BlockRead(F, Data[0], Math.min(byteSize(), blockSize), r);
  Result := r;
end;

function TTensor<T>.loadFromFile(const FileName: string; blockSize: SizeInt): SizeInt;
var
  F: file;
  r: integer;
begin
  assert(FileExists(FileName), 'File not found :' + FileName);
  if blockSize = 0 then blockSize := byteSize();
  try
    AssignFile(F, FileName);
    reset(F, 1);
    BlockRead(F, Data[0], Math.min(byteSize(), blockSize), r);
    Result := r
  finally
    CloseFile(F);
  end;
end;

function TTensor<T>.SaveToFile(var F: file; blockSize: SizeInt): SizeInt;
var
  r: integer;
begin
  if blockSize = 0 then blockSize := byteSize();
  BlockWrite(F, Data[0], Math.min(byteSize(), blockSize * sizeOf(T)), r);
  Result := r;
end;

procedure TTensor<T>.SaveToImage(const FileName: string; Index: SizeInt;
  const aNormalize: boolean);
var
  aMin, aMax, val, denom: T;
  x, y, imgs, c, f, t, argMin, argMax, _area: SizeInt;
  //  d   : double;
  b: byte;
  wd: word;
  {$if defined(FRAMEWORK_FMX)}
  pic: TBitmap;
  bmp: TBitmapData;
  D: PUInt32;
  {$elseif defined(FPC)}
  bmp : TFPMemoryImage;
  clr : TFPColor;
    d : double;
  {$elseif defined(FRAMEWORK_VCL)}
  bmp : TBitmap;
  D   : PUInt32;
  {$endif}
begin
  assert(Dimensions > 1, 'Tensor must have two dimenstions at least!');
  assert(index < Size() div area(), 'Image index out of range');
  imgs := Size() div area();
  if index < 0 then
  begin
    f := 0;
    t := Imgs - 1;
  end
  else
  begin
    f := index;
    t := index;
  end;
  {$if defined(FRAMEWORK_FMX)}
  pic := TBitmap.Create;
  //  pic.pixelFormat := TPixelFormat.BGRA;
  pic.resize(w(), imgs * h());
  pic.map(TMapAccess.ReadWrite, bmp);
  for c := f to t do
    for y := 0 to h() - 1 do
    begin
      D := bmp.getscanline(y);
      for x := 0 to w() - 1 do
      begin
        vcvtb(1, @Data[c * area() + y * w() + x], @b);
        D[c * area() + y * w() + x] := $ff000000 + b + b shl 8 + b shl 16;
      end;
    end;
  pic.unmap(bmp);
  try
    pic.SaveToFile(FileName);
  finally
    pic.Free
  end;
  {$elseif defined(FPC)}
  bmp := TFPMemoryImage.Create(w(), imgs*h());
  if aNormalize then begin
    if not assigned(minmaxvsi) then minmaxvsi := minMax;
  end;
  _area := area();
  for c :=f to t do begin
    if aNormalize then begin
      minmaxvsi(_area, @data[c*_area], 1, aMin, aMax, argMin, argMax);
      denom := minus(aMax, aMin);
    end;
    if aNormalize and (denom=0) then
      continue;
    for y := 0 to h()-1 do
      for x := 0 to w()-1 do begin
        if aNormalize then begin
          val := data[c*_area + y*w() + x];
          if denom<>0 then
            val := Division(minus(val, aMin), denom);
          vcvtd(1, @val, @d);
          b := trunc(d * $ff);
        end else
          vcvtb(1, @data[c*_area + y*w() + x], @b);
        wd := b shl 8;
        clr.red := wd; clr.Green := wd; clr.Blue := wd; clr.Alpha := $ff00;
        bmp.Colors[x, c * h() + y] := clr;
      end;
  end;
  try
    bmp.SaveToFile(FileName) ;
  finally
    bmp.free
  end;
  {$elseif defined(FRAMEWORK_VCL)}
  bmp := TBitmap.Create;
  bmp.pixelFormat := ps32bit;
  bmp.resize(w(), imgs*h());
  for c :=f to t do
    for y := 0 to h()-1 do begin
      D := bmp.scanline[y];
      for x := 0 to w()-1 do begin
        vcvtb(1, @data[c*area() + y*w() + x], @b);
        D[c * area() + y*w() +x] := $ff000000 + b + b shl 8 + b shl 16;
      end;
    end;
  try
    bmp.SaveToFile(FileName) ;
  finally
    bmp.free
  end;
  {$endif}
end;

procedure TTensor<T>.Add(const srcVector: PT; const dstOffset: SizeInt;
  N: SizeInt; const dstStride: SizeInt; const srcStride: SizeInt);
var
  i: SizeInt;
begin
  assert(dstOffset + N<=Size());
  if N <= 0 then N := Size() div dstStride;
  if assigned(addvv) then
  begin
    addvv(N, Data + dstOffset, dstStride, srcVector, srcStride, Data + dstOffset, dstStride);
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Plus(Data[i * dstStride], srcVector[i * srcStride]);
end;

procedure TTensor<T>.Subtract(const srcVector: PT; N: SizeInt;
  const dstStride: SizeInt; const srcStride: SizeInt);
var
  i: SizeInt;
begin
  if N <= 0 then N := Size() div dstStride;
  if assigned(mulvv) then
  begin
    subvv(N, Data, dstStride, srcVector, srcStride, Data, dstStride);
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Minus(Data[i * dstStride], srcVector[i * srcStride]);
end;

procedure TTensor<T>.Multiply(const srcVector: PT; N: SizeInt;
  const dstStride: SizeInt; const srcStride: SizeInt);
var
  i: SizeInt;
begin
  if N <= 0 then N := Size() div dstStride;
  if assigned(mulvv) then
  begin
    mulvv(N, Data, dstStride, srcVector, srcStride, Data, dstStride);
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Times(Data[i * dstStride], srcVector[i * srcStride]);
end;

procedure TTensor<T>.Divide(const srcVector: PT; N: SizeInt;
  const dstStride: SizeInt; const srcStride: SizeInt);
var
  i: SizeInt;
begin
  if N <= 0 then N := Size() div dstStride;
  if assigned(divvv) then
  begin
    divvv(N, Data, dstStride, srcVector, srcStride, Data, dstStride);
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Division(Data[i * dstStride], srcVector[i * srcStride]);
end;

procedure TTensor<T>.Add(const src: T; N: SizeInt; const dstStride: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opAddvs);
  {$endif}
  if N <= 0 then N := Size() div dstStride;
  if assigned(addvs) then
  begin
    addvs(N, src, Data, dstStride, Data, dstStride);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opAddvs);
    {$endif}
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Plus(Data[i * dstStride], src);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opAddvs);
  {$endif}
end;

procedure TTensor<T>.Subtract(const src: T; N: SizeInt; const dstStride: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opSubvs);
  {$endif}
  if N <= 0 then N := Size() div dstStride;
  if assigned(subvs) then
  begin
    subvs(N, src, Data, dstStride, Data, dstStride);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opSubvs);
    {$endif}
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Minus(src, Data[i * dstStride]);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opSubvs);
  {$endif}
end;

procedure TTensor<T>.Multiply(const src: T; N: SizeInt; const dstStride: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opMulvs);
  {$endif}
  if N <= 0 then N := Size() div dstStride;
  if assigned(mulvs) then
  begin
    {$ifdef _USE_OPENCL}
    if not wasGPU() then
      pushToDevice;
    ocl.scal(N, src, devData, dstStride);
    {$else}
    mulvs(N, src, Data, dstStride);
    {$endif}
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opMulvs);
    {$endif}
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Times(Data[i * dstStride], src);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opMulvs);
  {$endif}
end;

procedure TTensor<T>.Divide(const src: T; N: SizeInt; const dstStride: SizeInt);
var
  i: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opDivvs);
  {$endif}
  if N <= 0 then N := Size() div dstStride;
  if assigned(divvs) then
  begin
    divvs(N, src, Data, dstStride, Data, dstStride);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opDivvs);
    {$endif}
    exit;
  end;
  for i := 0 to N - 1 do
    Data[i * dstStride] := Division(src, Data[i * dstStride]);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opDivvs);
  {$endif}
end;

procedure TTensor<T>.FusedMultiplyAdd(const scale, bias: T;
  const offset: SizeInt; N: SizeInt; const stride: SizeInt);
var
  i: SizeInt;
  D: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opFmavss);
  {$endif}
  if N = 0 then N := Size() div stride;
  if assigned(fmavss) then
  begin
    fmavss(N, Data + offset, stride, scale, bias);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opFmavss);
    {$endif}
    exit;
  end;
  D := Data + offset;
  for i := 0 to N - 1 do
    D[i * stride] := Plus(Times(D[i * stride], Scale), Bias);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opFmavss);
  {$endif}
end;

procedure TTensor<T>.Add(const src: TTensor<T>; const offset: SizeInt;
  aSize: SizeInt);
var
  i, j, N, NBlocks, blockSize, grp, sd, Sc: SizeInt;
  _sum: T;
  D1, D2: PT;
  dstBatch: boolean;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opAddvv);
  {$endif}
  if aSize = 0 then aSize := Size();
  sd := aSize;
  sc := src.size();
  if sd = sc then
  {$ifdef USE_OPENCL}
    if computingDevice=cdOpenCL then begin
      if not wasGPU() then pushToDevice();
      if not src.wasGPU() then src.pushToDevice();
      ocl.addvv(sd, src.devData, 0, 1, devData, 0, 1, devData, 0, 1);
      exit;
    end else
  {$endif}
    begin
      assert(aSize + offset <= Size());
      addvv(aSize, Data + offset, 1, src.Data, 1, Data + offset, 1);
      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.finish(opAddvv);
      {$endif}
      exit;
    end;
  dstBatch := sd > sc;
  if (groups = src.groups) and (src.groups > 1) then
  begin
    NBlocks := sd div groups;
    blockSize := sc div groups;
    N := Math.min(NBlocks, blockSize);
    D1 := Data + offset;
    D2 := src.Data;
    for i := 0 to groups - 1 do
    begin
      addvv(N, D1, 1, D2, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, blockSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opAddvv);
    {$endif}
    exit;
  end;
  if dstBatch then
  begin
    NBlocks := sd;
    N := sc;
    grp := Groups;
    blockSize := NBlocks div (grp * N);
  end
  else
  begin
    NBlocks := sc;
    N := sd;
    grp := src.Groups;
    blockSize := NBlocks div (grp * N);
  end;
  Assert(grp * N * BlockSize = NBlocks, '[Add] : Tensor sizes doesn''t align');
  if dstBatch then    // forward bias
  begin
    assert(aSize + offset <= Size());
    {$ifdef _USE_OPENCL}
    if computingDevice=cdOpenCL then begin
      if not src.wasGPU() then
        src.pushToDevice;
      if not wasGPU then
        pushToDevice;
      ocl.forwardBias(sd, devData , sc, src.devData, 1, groups);
    end else
    {$endif}
      addblkvv(N, Data + offset , blockSize, src.Data, 1, groups);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opAddvv);
    {$endif}
    exit;
  end;
  {$if defined(_USE_OPENCL)}
  if computingDevice= cdOpenCL then begin
    if not src.wasGPU() then
      src.pushToDevice;
    if not wasGPU then
      pushToDevice;
    ocl.backwardBias(size(), devData, src.size(), src.devData, 1, src.groups);
  end
  else
  {$endif}
  begin
    blockSize := blockSize div src.steps;
    assert(NBLocks + offset <= src.Size());
    if not assigned(sumv) then sumv := TTensor<T>.sum;
    D1 := Data ;
    D2 := src.Data + offset;
    //if blockSize=1 then
    //  for i := 0 to N - 1 do
    //    data[i] := sumv(groups, src.data+ i , N)
    //else
    for i := 0 to N - 1 do
      begin
        _sum := Default(T);
        for j := 0 to src.groups - 1 do
          _sum := Plus(_sum, sumv(blockSize, D2 + (j * N + i) * blockSize, 1));
        D1[i] := Plus(D1[i], _sum);
      end
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opAddvv);
  {$endif}
end;

procedure TTensor<T>.Subtract(const src: TTensor<T>);
var
  i, N, blockSize, NBlocks: SizeInt;
  D1, D2: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opSubvv);
  {$endif}
  NBlocks := size();
  N := src.Size();
  if NBlocks = N then
  begin
    subvv(Size(), Data, 1, src.Data, 1, Data, 1);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opSubvv);
    {$endif}
    exit;
  end;
  if (groups = src.groups) and (src.Groups > 1) then
  begin
    NBlocks := NBlocks div groups;
    blockSize := N div groups;
    N := Math.min(NBlocks, blockSize);
    D1 := Data;
    D2 := src.Data;
    for i := 0 to groups - 1 do
    begin
      subvv(N, D1, 1, D2, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, blockSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opSubvv);
    {$endif}
    exit;
  end;
  blockSize := NBlocks div (Groups * N);
  Assert(Groups * N * BlockSize = NBlocks, '[Subtract] : Tensor sizes doesn''t align');
  for i := 0 to groups - 1 do
    subblkvv(N, Data + i * N * blockSize, blockSize, src.Data, 1);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opSubvv);
  {$endif}
end;

procedure TTensor<T>.Multiply(const src: TTensor<T>; const offset: SizeInt;
  aSize: SizeInt);
var
  i, N, blockSize, NBlocks: SizeInt;
  D1, D2: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opMulvv);
  {$endif}
  if aSize=0 then aSize := Size();
  assert(offset + aSize <= Size());
  NBlocks := aSize;
  N := src.Size();
  if NBlocks = N then
  begin
    mulvv(aSize, Data + offset, 1, src.Data, 1, Data + offset, 1);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opMulvv);
    {$endif}
    exit;
  end;
  if (groups = src.groups) and (src.groups > 1) then
  begin
    NBlocks := NBlocks div groups;
    blockSize := N div groups;
    N := Math.min(NBlocks, blockSize);
    D1 := Data + offset;
    D2 := src.Data;
    for i := 0 to groups - 1 do
    begin
      mulvv(N, D1, 1, D2, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, blockSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opMulvv);
    {$endif}
    exit;
  end;
  blockSize := NBlocks div (Groups * N);
  Assert(Groups * N * BlockSize = NBlocks, '[Multiply] : Tensor sizes doesn''t align');
  blockSize := blockSize div steps;
  D1 := Data + offset;
  for i := 0 to groups - 1 do
    mulblkvv(N, D1 + i * N * blockSize, blockSize, src.Data, 1);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opMulvv);
  {$endif}

end;

procedure TTensor<T>.Divide(const src: TTensor<T>);
var
  i, N, blockSize, NBlocks: SizeInt;
  D1, D2: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opDivvv);
  {$endif}
  NBlocks := size();
  N := src.Size();
  if NBlocks = N then
  begin
    divvv(Size(), Data, 1, src.Data, 1, Data, 1);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opDivvv);
    {$endif}
    exit;
  end;
  if (groups = src.groups) and (src.groups > 1) then
  begin
    NBlocks := NBlocks div groups;
    blockSize := N div groups;
    N := Math.min(NBlocks, blockSize);
    D1 := Data;
    D2 := src.Data;
    for i := 0 to groups - 1 do
    begin
      divvv(N, D1, 1, D2, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, blockSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opDivvv);
    {$endif}
    exit;
  end;
  blockSize := NBlocks div (Groups * N);
  Assert(Groups * N * BlockSize = NBlocks, '[Divide] : Tensor sizes doesn''t align');
  for i := 0 to groups - 1 do
    divblkvv(N, Data + i * N * blockSize, blockSize, src.Data, 1);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opDivvv);
  {$endif}

end;

procedure TTensor<T>.fusedMultiplyAdd(const scale, bias: TTensor<T>);
var
  i, N, blockSize, NBlocks: SizeInt;
  D1, D2, D3: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opBatchFmavss);
  {$endif}
  NBlocks := size();
  N := scale.Size();
  assert((N = bias.Size()) and (scale.groups = bias.groups));
  if (NBlocks = N) then
  begin
    mulvv(Size(), Data, 1, scale.Data, 1, Data, 1);
    addvv(Size(), Data, 1, bias.Data, 1, Data, 1);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opBatchFmavss);
    {$endif}
    exit;
  end;
  if (groups = scale.groups) and (scale.groups > 1) then
  begin
    NBlocks := NBlocks div groups;
    blockSize := N div groups;
    N := Math.min(NBlocks, blockSize);
    D1 := Data;
    D2 := scale.Data;
    D3 := bias.Data;
    for i := 0 to groups - 1 do
    begin
      mulvv(N, D1, 1, D2, 1, D1, 1);
      mulvv(N, D1, 1, D3, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, blockSize);
      Inc(D3, blockSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opBatchFmavss);
    {$endif}
    exit;
  end;
  blockSize := NBlocks div (Groups * N);
  Assert(Groups * N * BlockSize = NBlocks, '[Multiply] : Tensor sizes doesn''t align');
  for i := 0 to groups - 1 do
    //mulblkvv(N, Data + i * N * blockSize, blockSize, scale.Data, 1);
    mulAddBlkvv(N, Data + i * N * blockSize, blockSize, scale.Data, 1, bias.Data, 1);

  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opBatchFmavss);
  {$endif}
end;

procedure TTensor<T>.axpy(const a: T; const x: TTensor<T>);
var
  i, NBlocks, N, grp, sc, sd: SizeInt;
  dstBatch: boolean;
  D1, D2: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opAxpy);
  {$endif}
  if not Assigned(axpysvv) then axpysvv := axpy;
  sd := size();
  sc := x.size();
  if sc = sd then
  begin
    {$ifdef _USE_OPENCL}
    if not wasGPU() then pushToDevice;
    if not x.wasGPU() then x.pushToDevice;
    ocl.axpy(sd, a, x.devData, 1, devData, 1);
    {$else}
    axpysvv(sd, a, x.Data, 1, Data, 1);
    {$endif}
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opAxpy);
    {$endif}
    exit;
  end;
  if (groups = x.groups) and (x.groups > 1) then
  begin
    NBlocks := sd div groups;
    grp := sc div groups;
    N := Math.min(NBlocks, grp);
    D1 := Data;
    D2 := x.Data;
    for i := 0 to groups - 1 do
    begin
      axpysvv(N, a, D2, 1, D1, 1);
      Inc(D1, NBlocks);
      Inc(D2, grp);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opAxpy);
    {$endif}
    exit;
  end;

  dstBatch := groups > x.groups;
  if dstBatch then
  begin
    NBlocks := sd;
    N := sc;
    grp := Groups;
  end
  else
  begin
    NBlocks := sc;
    N := sd;
    grp := x.Groups;
  end;
  Assert(N * grp = NBlocks, '[axpy] batch * X tensor size doesn''t match Y Tensor size');
  if dstBatch then
    for i := 0 to grp - 1 do
      axpysvv(N, a, x.Data, 1, Data + i * N, 1)
  else
    for i := 0 to grp - 1 do
      axpysvv(N, a, x.Data + i * N, 1, Data, 1);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opAxpy);
  {$endif}
end;

function TTensor<T>.threshold(const AThreshold: T; const ifAbove: PT;
  const ifElse: PT; const stride: SizeInt): SizeInt;
begin
  if not assigned(threshv) then threshv := threshold;
  Result := threshv(Size(), Data, stride, AThreshold, ifAbove, ifElse);
end;

function TTensor<T>.absThreshold(const AThreshold: T; const ifAbove: PT;
  const ifElse: PT; const stride: SizeInt): SizeInt;
begin
  if not assigned(absthreshv) then absthreshv := absthreshold;
  Result := absThreshv(Size(), Data, stride, AThreshold, ifAbove, ifElse);
end;

procedure TTensor<T>.addSums(const src: TTensor<T>);
var
  b, i, N, nDst, blocksize: SizeInt;
  D: PT;
begin
  N := src.Size;
  nDst := Size;
  blockSize := N div (nDst * src.Groups);
  assert(N = src.groups * nDst * blockSize, '[addSum] : Tensor sizes doesn''t align');
  if not assigned(sumv) then sumv := TTensor<T>.Sum;
  // todo Optimize addSums
  for b := 0 to src.Groups - 1 do
    for i := 0 to nDst do
      Data[i] := plus(Data[i], sumv(blockSize, src.Data + (i + b * nDst) * blockSize, 1));
end;

procedure TTensor<T>.addDots(const src1, src2: TTensor<T>; const offset: SizeInt
  );
var
  b, i, idx, N, nDst, blocksize: SizeInt;
  sum: T;
begin
  N := src1.Size;
  assert((N = src2.size()) and (src1.groups = src2.groups),
    'Source tensors must have the same size and groups');
  nDst := Size;
  blockSize := N div (nDst * src1.Groups);
  assert(N = src1.groups * nDst * blockSize, '[addDot] : Tensor sizes doesn''t align');
  blockSize := blockSize div src1.steps;
  if not assigned(dotvv) then dotvv := TTensor<T>.dot;
  // todo Optimize addDots
  for i := 0 to nDst - 1 do
  begin
    sum := Default(T);
    for b := 0 to src1.Groups - 1 do
    begin
      idx := (i + b * nDst) * blockSize;
      sum := plus(sum, dotvv(blockSize, src1.Data + offset + idx, 1, src2.Data + offset + idx, 1));
    end;
    Data[i] := plus(Data[i], Sum);
  end;
end;

procedure TTensor<T>.blockAdd(const src: TTensor<T>; const blockSize: SizeInt);
var
  i, N, nDst: SizeInt;
begin
  N := src.Size();
  nDst := Size();
  Assert(Groups * N * blockSize = nDst,
    '[blockAdd] : Tensor size doesn''t match [Batch X Src] size');
  i := 0;
  while i < nDst do
  begin
    addblkvv(N, Data + i, blockSize, src.Data, 1);
    Inc(i, N * blockSize);
  end;
end;

procedure TTensor<T>.blockSubtract(const src: TTensor<T>; const blockSize: SizeInt);
var
  i, N, nDst: SizeInt;
begin
  N := src.Size();
  nDst := Size();
  Assert(Groups * N * blockSize = nDst,
    '[blockSubtract] : Tensor size doesn''t match [Batch X Src] size');
  i := 0;
  while i < nDst do
  begin
    subblkvv(N, Data + i, blockSize, src.Data, 1);
    Inc(i, N * blockSize);
  end;
end;

procedure TTensor<T>.blockMultiply(const src: TTensor<T>; const blockSize: SizeInt);
var
  i, N, nDst: SizeInt;
begin
  N := src.Size();
  nDst := Size();
  Assert(Groups * N * blockSize = nDst,
    '[blockMultiply] : Tensor size doesn''t match [Batch X Src] size');
  i := 0;
  while i < nDst do
  begin
    mulblkvv(N, Data + i, blockSize, src.Data, 1);
    Inc(i, N * blockSize);
  end;
end;

procedure TTensor<T>.blockDivide(const src: TTensor<T>; const blockSize: SizeInt);
var
  i, N, nDst: SizeInt;
begin
  N := src.Size();
  nDst := Size();
  Assert(Groups * N * blockSize = nDst,
    '[blockDivide] : Tensor size doesn''t match [Batch X Src] size');
  i := 0;
  while i < nDst do
  begin
    divblkvv(N, Data + i, blockSize, src.Data, 1);
    Inc(i, N * blockSize);
  end;
end;

procedure TTensor<T>.&or(const a: T; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(orvs), 'Not Implemented');
  if N = 0 then N := Size - start;
  orvs(N, a, Data + start, 1);
end;

procedure TTensor<T>.&and(const a: T; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(andvs), 'Not Implemented');
  if N = 0 then N := Size - start;
  andvs(N, a, Data + start, 1);
end;

procedure TTensor<T>.&xor(const a: T; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(xorvs), 'Not Implemented');
  if N = 0 then N := Size - start;
  xorvs(N, a, Data + start, 1);
end;

procedure TTensor<T>.&not(const dst: PT; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(notv), 'Not Implemented');
  if N = 0 then N := Size - start;
  notv(N, Data + start, 1, dst, 1);
end;

procedure TTensor<T>.&or(const a: PT; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(orvv), 'Not Implemented');
  if N = 0 then N := Size - start;
  orvv(N, a, 1, Data + start, 1);
end;

procedure TTensor<T>.&and(const a: PT; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(andvv), 'Not Implemented');
  if N = 0 then N := Size - start;
  andvv(N, a, 1, Data + start, 1);
end;

procedure TTensor<T>.&xor(const a: PT; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(xorvv), 'Not Implemented');
  if N = 0 then N := Size - start;
  xorvv(N, a, 1, Data + start, 1);
end;

procedure TTensor<T>.&shr(const a: T; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(shrvs), 'Not Implemented');
  if N = 0 then N := Size - start;
  shrvs(N, a, Data + start, 1);
end;

procedure TTensor<T>.&shl(const a: T; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(shlvs), 'Not Implemented');
  if N = 0 then N := Size - start;
  shlvs(N, a, Data + start, 1);
end;

procedure TTensor<T>.toBytes(const dst: pbyte; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(vcvtb), 'Not Implemented');
  if N = 0 then N := Size - Start;
  vcvtb(N, @Data[start], dst);
end;

procedure TTensor<T>.toInts(const dst: PInt32; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(vcvti32), 'Not Implemented');
  if N = 0 then N := Size - Start;
  vcvti32(N, @Data[start], dst);
end;

procedure TTensor<T>.toSingles(const dst: PSingle; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(vcvts), 'Not Implemented');
  if N = 0 then N := Size - Start;
  vcvts(N, @Data[start], dst);
end;

procedure TTensor<T>.toDoubles(const dst: PDouble; const start: SizeInt; N: SizeInt);
begin
  assert(assigned(vcvtd), 'Not Implemented');
  if N = 0 then N := Size - Start;
  vcvtd(N, @Data[start], dst);
end;

function TTensor<T>.dot(const src: PT; N: SizeInt; const Stride: SizeInt;
  const srcStride: SizeInt): T;
begin
  if N < 0 then
    N := Size() div Stride;
  if not assigned(dotvv) then dotvv := dot;
  exit(dotvv(N, Data, Stride, src, srcStride));

end;

function TTensor<T>.sumSqrDiff(const src: PT; N: SizeInt; const Stride: SizeInt;
  const srcStride: SizeInt): T;
begin
  if N < 0 then
    N := Size() div Stride;
  if not assigned(sumsqrdiffvv) then sumsqrdiffvv := sumSqrDiff;
  exit(sumsqrdiffvv(N, Data, Stride, src, srcStride));
end;

function TTensor<T>.sumSqrDiff(const src: T; const Stride: SizeInt): T;
begin
  if not assigned(sumsqrdiffv) then sumsqrdiffv := sumSqrDiff;
  exit(sumsqrdiffv(size() div stride, src, Data, stride));
end;

function TTensor<T>.sumAbsDiff(const src: PT; N: SizeInt;
  const Stride: SizeInt; const srcStride: SizeInt): T;
begin
  if N < 0 then
    N := Size() div Stride;
  if not assigned(sumabsdiffvv) then sumabsdiffvv := sumAbsDiff;
  exit(sumabsdiffvv(N, Data, Stride, src, srcStride));
end;

function TTensor<T>.sumAbsDiff(const src: T; const Stride: SizeInt): T;
begin
  if not assigned(sumabsdiffv) then sumsqrdiffv := sumabsDiff;
  exit(sumabsdiffv(size() div stride, src, Data, stride));
end;

procedure TTensor<T>.matMul(const mat, dstMat: TTensor<T>;
  const transA: CBLAS_TRANSPOSE; transB: CBLAS_TRANSPOSE);
var
  M, N, K, lda, ldb, ldc: SizeInt;
  b, batchs, bSize, cSize: SizeInt;
begin
  //     K          N          N
  //   [...]      [...]      [...]
  // M [.A.]  X K [.B.] => M [.C.]
  //   [...]      [...]      [...]

  assert((mat.Dimensions < 3), 'Tensors must have two dimensions');
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opGemm);
  {$endif}

  if transA = CblasTrans then
  begin
    M := w;
    K := h;
    lda := M;  // h;
  end
  else
  begin
    M := h;
    K := w;
    lda := K;   // w;
  end;
  if transB = CblasTrans then
  begin
    N := mat.h;
    ldb := K;     // mat.h;
  end
  else
  begin
    N := mat.w;
    ldb := N;// mat.w
  end;
  ldc := N;

  case mat.Dimensions of
    1:
    begin
      gemm(CblasRowMajor, transA, transB,
        M, 1, K, One,
        Data, lda,
        mat.Data, 1,
        One,
        dstMat.Data, 1
        );
      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.finish(opGemm);
      {$endif}
      exit;
    end;
    2:
    begin
      gemm(CblasRowMajor, transA, transB,
        M, N, K, One,
        Data, lda,
        mat.Data, ldb,
        One,
        dstMat.Data, ldc
        );
      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.finish(opGemm);
      {$endif}
      exit;
    end;
  end;
  bSize := mat.groupSize();
  batchs := mat.Size() div bSize;
  assert((batchs = mat.groups) and (mat.groups = dstMat.groups),
    'matMul : Matrix groups does not equal the number of batchs.');
  cSize := dstMat.groupSize();
  for b := 0 to batchs - 1 do
  begin
    gemm(CblasRowMajor, transA, transB,
      M, N, K, One,
      Data, lda,
      mat.Data + b * bSize, ldb,
      One,
      dstMat.Data + b * cSize, ldc
      );
  end;

  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opGemm);
  {$endif}
end;

function TTensor<T>.matMul(const mat: TTensor<T>; const transA: CBLAS_TRANSPOSE;
  transB: CBLAS_TRANSPOSE): TTensor<T>;
var
  M, N, K, lda, ldb, ldc: SizeInt;
begin
  //{$ifdef USE_TELEMETRY}
  //if benchmark then tensorMetrics.start(opGemm);
  //{$endif}

  assert(mat.dimensions <= 2, '[matMul] matrix [b] must have one or two dimensions.');
  if transA = CblasTrans then
  begin
    M := w;
    K := h;
    lda := M;  // h;
  end
  else
  begin
    M := h;
    K := w;
    lda := K;   // w;
  end;
  if transB = CblasTrans then
  begin
    N := mat.h;
    ldb := K;     // mat.h;
  end
  else
  begin
    N := mat.w;
    ldb := N;// mat.w
  end;
  ldc := N;
  if mat.dimensions = 1 then
    Result.resize([M])
  else
    Result.resize([M, N]);
  matMul(mat, Result, transA, transB);
  //{$ifdef USE_TELEMETRY}
  //if benchmark then tensorMetrics.finish(opGemm);
  //{$endif}
end;

function TTensor<T>.matDeterminant: T;
begin
  Result := matDet(Data, w);
end;

procedure TTensor<T>.matDeterminant(var dst: PT);
var
  i, N: SizeInt;
begin
  assert(length(FShape) > 1, 'Tensor is a vector');
  N := Size() div Area();
  for i := 0 to N - 1 do
    dst[i] := matDet(Data, w);
end;

procedure TTensor<T>.matInverse(const dst: TTensor<T>);
var
  i, N, _area, _w: SizeInt;
begin
  assert(Dimensions > 1, 'Tensor is a vector');
  _area := Area;
  _w := w();
  N := Size() div _area;
  for i := 0 to N - 1 do
    matInv(@Data[i * _area], @dst.Data[i * _area], _w);
end;

function TTensor<T>.matInverse(): TTensor<T>;
var
  i, N, _area, _w: SizeInt;
begin
  Result.resize(FShape, groups);
  _area := Area;
  _w := w();
  N := Size() div _area;
  for i := 0 to N - 1 do
    matInv(@Data[i * _area], @Result.Data[i * _area], _w);
end;

function TTensor<T>.matDegrade(const row, col: SizeInt): TTensor<T>;
begin
  Result.reSize([w - 1, w - 1]);
  matDeg(Data, Result.Data, w, row, col);
end;

procedure TTensor<T>.matTranspose(const dst: TTensor<T>);
var
  i, N, _area, _h, _w: SizeInt;
begin
  Assert(Dimensions > 1, 'Tensor is a vector');
  _Area := Area();
  _h := h();
  _w := w();
  N := Size() div _Area;
  for i := 0 to N - 1 do
    matTra(@Data[i * _area], @dst.Data[i * _area], _h, _w);
end;

function TTensor<T>.matTranspose(): TTensor<T>;
var
  shp: TSizes;
  N: SizeInt;
begin
  shp := copy(FShape);
  n := high(shp);
  shp[n] := FShape[n - 1];
  shp[n - 1] := FShape[n];
  Result.resize(shp, groups);
  matTranspose(Result);
end;

function TTensor<T>.SolveLeastSquares(const b: PT; var coef: PT): integer;
begin

end;

procedure TTensor<T>.Conv2D(const AKernels, dst: TTensor<T>;
  wPadding: SizeInt; hPadding: SizeInt; xStride: SizeInt; yStride: SizeInt;
  xDilation: SizeInt; yDilation: SizeInt);
var
  kSize: SizeInt;
  b, imColSize, k, filters, outImgSize, filt, chan: SizeInt;
  srcIm, dstIm, ker: PT;
  mt: boolean;
  aOffset, bOffset : SizeInt;  t:TSingleTensor;
  {$ifdef USE_OPENCL}
  _A, _B, _C: TCLMemory;
  {$endif}
begin
  assert((AKernels.dimensions > 1) and (Dimensions > 1) and (dst.dimensions > 1));
  if wPadding < 0 then
    wPadding := xDilation + AKernels.w() div 2 - 1;
  if hPadding < 0 then
    hPadding := yDilation + AKernels.h() div 2 - 1;
  assert(w() div xStride + wPadding * 2 - AKernels.w() + 1 = dst.w());
  assert(h() div yStride + hPadding * 2 - AKernels.h() + 1 = dst.h());
  assert((AKernels.c() = dst.c()) and (AKernels.n() = c()));
  kSize := AKernels.area();
  outImgSize := dst.area();
  filters := AKernels.c();
  k := c * kSize;
  imColSize := c() * kSize * outImgSize;
  if ((kSize <> 1) or (xDilation * yDilation <> 1) or (xStride * yStride <> 1)) and
    (length(workspace) < groups*imColSize) then
  begin
    //writeln('Reallocating.. Actual: ',length(workSpace), ' Required: ', imColSize);
    setLength(workspace, groups * imColSize);
    {$if defined(USE_CUDNN)}
    {$elseif defined(_USE_OPENCL) and not defined(CLBLASTCONV)}
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.start(opGPURelease);
    {$endif}
    if assigned(devWorkspace) then
      ocl.freeDeviceBuffer(devWorkspace);
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opGPURelease);
    {$endif}
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.start(opGPUAllocate);
    {$endif}
    devWorkspace := ocl.createDeviceBuffer(groups * imColSize * SizeOf(T));ocl.CheckError();
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opGPUAllocate);
    {$endif}
    {$endif}
  end;
  {$if defined(USE_CUDNN)}
  {$elseif defined(_USE_OPENCL)}
  if computingDevice = cdOpenCL then begin
    {$ifdef CLBLASTCONV}
    //if not wasGPU() then
    //  pushToDevice;
  // todo remove comment below when tensor GPU ops is complete
    //if not weights.wasGPU() then
      //AKernels.pushToDevice;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.start(opConv2D);
    {$endif}
    ocl.FErr := integer(CLBlastSconvgemm(CLBlastKernelModeCrossCorrelation, c, h, w, AKernels.h(), AKernels.w(), hPadding, wPadding, yStride, xStride, yDilation, xDilation, filters, groups, devData, 0, AKernels.devData, 0, dst.devData, 0, @ocl.ActiveQueue, @ocl.event[0])); ocl.CheckError();
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opConv2D);
    {$endif}
    dst.setOCL;
    {$else}
    if not wasGPU() then
      pushToDevice;
    if not AKernels.wasGPU() then
      AKernels.pushToDevice;
    for b := 0 to groups - 1 do
    begin
      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.start(opIm2col);
      {$endif}
      bOffset := 0;
      if (kSize <> 1) or (xStride * yStride <> 1) or (xDilation * yDilation <> 1) then
        begin
          _A := devData;
          _B := devWorkspace;
          aOffset := b * volume();
          bOffset := b * imColSize;
          ocl.FErr := integer(CLBlastSim2col(CLBlastKernelModeCrossCorrelation,
            c, h, w, AKernels.h(), AKernels.w(), hPadding, wPadding, yStride,
            xStride, yDilation, xDilation, _A, aOffset, _B, bOffset, @ocl.ActiveQueue, @ocl.events[0])); ocl.CheckError();
        end
      else
        begin
          _B := devData;
          bOffset := b * volume();
        end;
      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.finish(opIm2col);
      {$endif}

      {$ifdef USE_TELEMETRY}
      if benchmark then tensorMetrics.start(opGemm);
      {$endif}
      _C := dst.devData;
      ocl.FErr := integer(CLBlastSgemm(CLBlastLayoutRowMajor, CLBlastTransposeNo,
        CLBlastTransposeNo, filters, outImgSize, k, 1, AKernels.devData, 0,
        k, _B, bOffset, outImgSize, 0, _C, b * outImgSize * filters, outImgSize,
        @ocl.ActiveQueue, @ocl.events[0]));
      //ocl.gemm(filters, outImgSize, k, 1, AKernels.devData, k, _B, outImgSize, _C, outImgSize);
      ocl.CheckError();
      {$ifdef USE_TELEMETRY}
        if benchmark then tensorMetrics.finish(opGemm);
      {$endif}
    end;
    dst.setOCL;
    {$endif CLBLASTCONV}
    //if dst.wasGPU then
    //  dst.pullFromDevice;
  end else
  {$endif}
  begin
    mt := groups=1;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.start(opIm2col);
    {$endif}
    if (kSize <> 1) or (xDilation*yDilation<>1) or (xStride*yStride<>1) then begin
      bOffset := imColSize ;
      for b:=0 to groups-1 do
        im2Colvv(c, h, w, AKernels.h, aKernels.w, hPadding, wPadding, yStride, xStride, xDilation, yDilation, data, b*volume(), pointer(workspace), b * bOffset, 1, mt);
      srcIm := pointer(workspace);
    end else begin
      bOffset := volume();
      srcIm := data
    end;
    dstIM := dst.data;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opIm2col);
    {$endif}

    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.start(opGemm);
    {$endif}
    for b:=0 to groups-1 do begin
      gemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, filters, outImgSize, k, one, AKernels.data, k, srcIM + b * bOffset , outImgSize, zero, dstIM + b*outImgSize*filters, outImgSize);
    end;
    {$ifdef USE_TELEMETRY}
    if benchmark then tensorMetrics.finish(opGemm);
    {$endif}
  end
  //for b:=0 to groups-1 do
  //  for chan :=0 to c()-1 do begin
  //    srcIM := data + b * groupSize() + chan*area() ;
  //    for filt:= 0 to filters -1 do begin
  //      dstIM := b * dst.groupSize() + dst.data + filt*dst.area();
  //      ker := AKernels.data + chan*AKernels.volume() + filt*AKernels.area();
  //      _conv2d(srcIM, ker, dstIM, w(), h(),  aKernels.w(), aKernels.h(), wPadding, hPadding, xStride, yStride, xDilation, yDilation)
  //    end;
  //  end;

end;

procedure TTensor<T>.Abs(const stride: SizeInt);
begin
  assert(assigned(absv), '[Abs] : not implemented for this tensor type');
  absv(Size() div stride, pointer(Data), stride, pointer(Data), stride);
end;

procedure TTensor<T>.sumAbs(var dst: PT);
var
  i, N: SizeInt;
begin
  if not assigned(asumv) then asumv := sumAbs;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := asumv(N, Data + i * N, 1);
end;

function TTensor<T>.sumAbs(const stride: SizeInt): T;
begin
  if not assigned(asumv) then asumv := sumAbs;
  Result := asumv(Size(), Data, stride);
end;

procedure TTensor<T>.sumSquares(var dst: PT; const stride: SizeInt);
var
  i, N: SizeInt;
begin
  if not assigned(sumsqrv) then sumsqrv := sumsqr;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := sumsqrv(N div stride, Data + i * N, stride);
end;

function TTensor<T>.sumSquares(const stride: SizeInt): T;
begin
  if not assigned(sumsqrv) then sumsqrv := sumsqr;
  Result := sumsqrv(Size() div stride, Data, stride);
end;

procedure TTensor<T>.absDiff(const x: TTensor<T>; const stride: SizeInt);
begin
  assert(assigned(absdiffv), '[absDiff] : not implemented for this tensor type');
  absdiffv(Size() div stride, pointer(Data), stride, pointer(x.Data), stride);
end;

procedure TTensor<T>.square(const Stride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(sqrv) then
  begin
    sqrv(Size() div Stride, Data, Stride, Data, Stride);
    exit;
  end;
  for i := 0 to Size() div Stride - 1 do
    Data[i * Stride] := sqr(Data[i * Stride]);
end;

procedure TTensor<T>.square(var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(sqrv) then
  begin
    sqrv(Size() div srcStride, Data, srcStride, dst, dstStride);
    exit;
  end;
  for i := 0 to Size() div srcStride - 1 do
    dst[i * dstStride] := sqr(Data[i * srcStride]);
end;

procedure TTensor<T>.squareRoot(const Stride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(sqrtv) then
  begin
    sqrtv(Size() div stride, Data, Stride, Data, stride);
    exit;
  end;
  for i := 0 to Size() div Stride - 1 do
    Data[i * stride] := sqrt(Data[i * stride]);
end;

procedure TTensor<T>.squareRoot(var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(sqrtv) then
  begin
    sqrtv(Size() div srcStride, Data, srcStride, dst, dstStride);
    exit;
  end;
  for i := 0 to Size() div srcStride - 1 do
    dst[i * dstStride] := sqrt(Data[i * srcStride]);
end;

procedure TTensor<T>.ln(const stride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(logv) then
  begin
    logv(Size div stride, Data, stride, Data, stride);
    exit;
  end;

  for i := 0 to Size() div stride - 1 do
    Data[i * stride] := log(Data[i * stride]);
end;

procedure TTensor<T>.ln(const a: T; var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(expv) then
  begin
    expv(Size() div srcStride, Data, srcStride, dst, dstStride);
    exit;
  end;

  for i := 0 to Size div srcStride - 1 do
    dst[i * dstStride] := exp(Data[i * srcStride]);
end;

procedure TTensor<T>.Exponent(const stride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(expv) then
  begin
    expv(Size div stride, Data, stride, Data, stride);
    exit;
  end;

  for i := 0 to Size div stride - 1 do
    Data[i * stride] := exp(Data[i * stride]);
end;

procedure TTensor<T>.Exponent(const a: T; var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
var
  i: SizeInt;
begin
  if assigned(expv) then
  begin
    expv(Size div srcStride, Data, srcStride, dst, dstStride);
    exit;
  end;

  for i := 0 to Size div srcStride - 1 do
    dst[i * dstStride] := exp(Data[i * srcStride]);
end;

procedure TTensor<T>.power(const a: T; const stride: SizeInt);
begin
  assert(assigned(powv), '[Power] not implement!');
  powv(Size() div stride, a, Data, stride, Data, stride);
end;

procedure TTensor<T>.power(const a: T; var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(powv), '[Power] not implement!');
  powv(Size() div srcStride, a, Data, srcStride, dst, dstStride);
end;

procedure TTensor<T>.logN(const a: T; const stride: SizeInt);
begin
  assert(assigned(logv), '[Log] not implement!');
  lognv(Size() div stride, a, Data, stride, Data, stride);
end;

procedure TTensor<T>.logN(const a: T; var dst: PT; const srcStride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(logv), '[Power] not implement!');
  lognv(Size() div srcStride, a, Data, srcStride, dst, dstStride);
end;

function TTensor<T>.ResidualSumSquares(const Mean: T): T;
begin
  // todo [ResidualSumSquares] handl dst tensor
  if not Assigned(rssv) then rssv := rss;
  Result := rssv(Size, Mean, Data, 1);
end;

procedure TTensor<T>.Normalize(const aMean, aStdDev: T);
var
  i: SizeInt;
begin
  if assigned(normvss) then
    normvss(Size(), Data, aMean, aStdDev)
  else
    for i := 0 to Size() - 1 do
      Data[i] := Division(Minus(Data[i], aMean), aStdDev);
end;

procedure TTensor<T>.Normalize();
var
  i: SizeInt;
  aMean, aStdDev: T;
begin
  MeanAndVar(aMean, aStdDev);
  if aStdDev=0 then exit;
  aStdDev := Self.sqrt(aStdDev);
  if assigned(normvss) then
    normvss(Size(), Data, aMean, aStdDev)
  else
    for i := 0 to Size() - 1 do
      Data[i] := Division(Minus(Data[i], aMean), aStdDev);
end;

procedure TTensor<T>.maxNormalize(const aScale: T);
var
  N, i: SizeInt;
  amin, amax, dnom: T;
  armin, armax: SizeInt;
begin
  N := groupSize();
  if not assigned(minmaxvsi) then minmaxvsi := minMax;
  for i := 0 to Groups - 1 do
  begin
    minmaxvsi(N, Data + i * N, 1, amin, amax, arMin, arMax);
    dnom := division(aScale, minus(amax, amin));
    amin := minus(zero, aMin);
    addvs(N, amin, Data + i * N, 1, Data + i * N, 1);
    mulvs(N, dnom, Data + i * N, 1);
  end;
end;

procedure TTensor<T>.Normalize(const aMean, aStdDev: TTensor<T>;
  const offset: SizeInt; aSize: SizeInt);
var
  i, blockSize, N: SizeInt;
  D: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opNormalize);
  {$endif}
  N := aMean.Size();
  assert(aMean.Size() = aStdDev.Size(),
    'NORMALIZE : [Mean] and [StdDev] Tensor sizes do not match.');
  if aSize=0 then aSize := Size();
  blockSize := aSize div (Groups * N);
  assert(Groups * N * blockSize = aSize, 'NORMALIZE : Tensor sizes must align.');
  D := Data + offset;
  if blockSize = 1 then
    for i := 0 to Groups - 1 do
      normvv(N, aMean.Data, 1, aStdDev.Data, 1, D + i * N, 1)
  else
    for i := 0 to Groups - 1 do
      normblkvv(N, aMean.Data, 1, aStdDev.Data, 1, D + i * blockSize * N, blockSize);
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opNormalize)
  {$endif}
end;

{$ifdef CPUX64}
function sVarinceDelta(const N:SizeInt; const aMean:single; const delta, x:PSingle):single;assembler;
asm
  mov          rax      ,    N
  vbroadcastss ymm1     ,    aMean
  vxorps       ymm0     ,    ymm0,  ymm0
  shr          rax      ,    3  // div 8
  jz           @rem1
@while1:
  vmovups      ymm2     ,    yword[x]
  vsubps       ymm2     ,    ymm2,  ymm1
  vmulps       ymm2     ,    ymm2,  yword[delta]
  vaddps       ymm0     ,    ymm0,  ymm2
  add          x        ,    8*4
  add          delta    ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done
  vextractf128 xmm2     ,    ymm0,  1
  vzeroupper
  addps        xmm0     ,    xmm2
@while2:
  movss        xmm2     ,    dword[x]
  vsubss       xmm2     ,    xmm2,  xmm1
  vmulss       xmm2     ,    xmm2,  dword[delta]
  vaddss       xmm0     ,    xmm0,  xmm2
  add          x        ,    4
  add          delta    ,    4
  dec          rax
  jnz         @while2
@done:
  haddps       xmm0     ,    xmm0
  haddps       xmm0     ,    xmm0
end;

//type mm8 = array[0..7] of single; pm8=^mm8;

procedure sNormalizeDelta_avx(const N:SizeInt; const meanDelta, varDelta, aMean, aStdDev : single; delta:PSingle; const x:PSingle); assembler;
asm

  mov          rax      ,    N
  vbroadcastss ymm0     ,    meanDelta
  vbroadcastss ymm1     ,    varDelta
  vbroadcastss ymm2     ,    aMean
  rcpss        xmm3     ,    dword aStdDev
  vbroadcastss ymm3     ,    xmm3

  shr          rax      ,    3  // div 8
  jz           @rem1
  //  Delta.Data[index] / (sqrt(variance.Data[i] + sEPSILON)) +
  //        (2 * variance_delta.Data[i] * (x.Data[index] - mean.Data[i]) + mean_delta.Data[i]) / batchSize;
@while1:
  vmovups      ymm4     ,    yword  [delta]
  vmulps       ymm4     ,    ymm4,  ymm3           // delta / aStdDev
  vmovups      ymm5     ,    yword  [x]
  vsubps       ymm5     ,    ymm5,  ymm2           //  x - amean
  vmulps       ymm5     ,    ymm5,  ymm1           // (x - amean) * 2 * varDelta
  vaddps       ymm5     ,    ymm5,  ymm0           // + meanDelta => ymm5
  vaddps       ymm4     ,    ymm4,  ymm5           // + ymm5
  vmovups      yword  [delta]    ,  ymm4
  add          x        ,    8*4
  add          delta    ,    8*4
  dec          rax
  jnz         @while1

@rem1:
  mov          rax       ,    N
  and          rax       ,    7
  jz           @done

  @while2:
  movss        xmm4     ,    dword  [delta]
  vmulss       xmm4     ,    xmm4,  xmm3           // delta / aStdDev
  movss        xmm5     ,    dword  [x]
  vsubss       xmm5     ,    xmm5,  xmm2           //  x - amean
  vmulss       xmm5     ,    xmm5,  xmm1           // (x - amean) * 2 * varDelta
  vaddss       xmm5     ,    xmm5,  xmm0           // + meanDelta => xmm5
  vaddss       xmm4     ,    xmm4,  xmm5           // + xmm5
  movss        dword [delta]     ,  xmm4

  add          x        ,    4
  add          delta    ,    4
  dec          rax
  jnz         @while2
@done:

end;
{$endif}

procedure sNormalizeDelta_pas(const N:SizeInt; const meanDelta, varDelta, aMean, aStdDev : single; delta:PSingle; const x:PSingle);
var i:SizeInt;
begin
  for i:=0 to N-1 do
        Delta[i] := Delta[i] / aStdDev +
          (varDelta * (x[i] - aMean) + meanDelta);
end;

procedure sMeanAndVarianceDelta(const delta, x, mean, variance: TTensor<single>;
  const mean_delta, variance_delta: TTensor<single>; const offset : SizeInt =0);
var
  i, j, k, N, nDst, blockSize, index: SizeInt;
  m, v: single;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opMeansVarsDelta);
  {$endif}
  N := Delta.Size();
  nDst := mean.Size();
  blockSize := N div (nDst * Delta.groups);

  Assert((N = nDst * Delta.Groups * blockSize) and (x.Size() = N) and
    (mean.Size = nDst) and (variance.Size = nDst) and
    (mean_delta.size = nDst) and (variance_delta.size() = nDst),
    '[MeanAndVarDelta] Tensor sizes must be aligned.');
  blockSize := blockSize div delta.steps;
  for i := 0 to nDst - 1 do
  begin
    m := 0;
    v := 0;
    for j := 0 to Delta.groups - 1 do begin
      m := m + vsSumI(blockSize, Delta.Data + offset + (i + j * nDst) * blockSize, 1);
      {$ifdef CPUX64}
      if AVX2Support then begin
        index := (i + j*nDst)*blockSize;
        v := v + sVarinceDelta(blockSize, mean.data[i], Delta.data + offset + index, x.Data + index);
      end else
      {$endif}
      for k := 0 to blockSize - 1 do begin
        index := (i + j * nDst) * blockSize + k;
        //m := m + Delta.Data[index];
        v := v + Delta.Data[index + offset] * (x.Data[index + offset] - mean.Data[i]);
      end;
    end;
    mean_delta.Data[i] := m * (-1.0 / sqrt(max(variance.Data[i] , sEPSILON)));
    variance_delta.Data[i] := v * -0.5 * Power(max(variance.Data[i] , sEPSILON), -3.0 / 2.0);
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opMeansVarsDelta)
  {$endif}
end;


procedure sNormalizeDelta(const x, mean, variance, mean_delta,
  variance_delta: TTensor<single>; const Delta: TTensor<single>; const offset:SizeInt =0);
var
  i, j, k, N, NBlocks, blockSize, batchSize, index: SizeInt;
  dd, xx:PSingle;
begin

  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opNormalizeDelta);
  {$endif}
  // todo [sNormalizeDelta] check two cases , if src has group>1 or dst group >1
  N := mean.Size();
  NBlocks := Delta.Size();
  blockSize := NBlocks div (N * Delta.groups);
  Assert((NBlocks = N * Delta.Groups * blockSize) and
    (x.Size() = NBlocks) and (mean.Size = N) and
    (variance.Size = N) and (mean_delta.size = N) and
    (variance_delta.size() = N), '[normalizeDelta] Tensor sizes must be aligned.');
  blockSize := blockSize div delta.steps;
  batchSize := blockSize * Delta.groups;
  for j := 0 to Delta.groups - 1 do
    for i := 0 to N - 1 do begin
      index := (i + j * N) * blockSize;
      dd := delta.Data + offset + index;
      xx := x.Data + offset + index;
      {$ifdef _CPUX64}  //todo : sNormalizeDelta_avx is not stable yet, revisit
      if AVX2Support then begin
        sNormalizeDelta_avx(blockSize, mean_delta.data[i]/batchSize, 2*variance_delta.data[i]/batchSize, mean.data[i], sqrt(max(variance.Data[i], sEPSILON)), dd, xx);
      end else
      {$endif}
        sNormalizeDelta_pas(blockSize, mean_delta.data[i]/batchSize, 2*variance_delta.data[i]/batchSize, mean.data[i], sqrt(max(variance.Data[i], sEPSILON)), dd, xx);
      //for k := 0 to blockSize - 1 do begin
      //  dd[k] :=
      //    dd[k] / sqrt(max(variance.Data[i] , sEPSILON)) +
      //    (2 * variance_delta.Data[i] * (xx[k] - mean.Data[i]) + mean_delta.Data[i]) / batchSize;
      //end;
    end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opNormalizeDelta)
  {$endif}

end;

procedure dMeanAndVarianceDelta(const delta, x, mean, variance: TTensor<double>;
  const mean_delta, variance_delta: TTensor<double>; const offset :SizeInt=0);
var
  i, j, k, N, nDst, blockSize, index: SizeInt;
  m, v: double;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opMeansVarsDelta);
  {$endif}
  N := Delta.Size();
  nDst := mean.Size();
  blockSize := N div (nDst * Delta.groups);

  Assert((N = nDst * Delta.Groups * blockSize) and (x.Size() = N) and
    (mean.Size = nDst) and (variance.Size = nDst) and
    (mean_delta.size = nDst) and (variance_delta.size() = nDst),
    '[MeanAndVarDelta] Tensor sizes must be aligned.');

  for i := 0 to nDst - 1 do
  begin
    m := 0;
    v := 0;
    for j := 0 to Delta.groups - 1 do
      for k := 0 to blockSize - 1 do
      begin
        index := (i + j * nDst) * blockSize + k;
        m := m + Delta.Data[index + offset];
        v := v + Delta.Data[index + offset] * (x.Data[index + offset] - mean.Data[i]);
      end;
    mean_delta.Data[i] := m * (-1. / sqrt(variance.Data[i] + 0.00001));
    variance_delta.Data[i] := v * -0.5 * Power(variance.Data[i] + 0.00001, -3.0 / 2.0);
  end;

  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opMeansVarsDelta)
  {$endif}
end;

procedure dNormalizeDelta(const x, mean, variance, mean_delta,
  variance_delta: TTensor<double>; const Delta: TTensor<double>; const offset :SizeInt =0);
var
  i, j, k, N, nDst, blockSize, batchSize, index: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opNormalizeDelta);
  {$endif}
  N := mean.Size();
  nDst := Delta.Size();
  blockSize := nDst div (N * Delta.groups);
  Assert((N = nDst * Delta.Groups * blockSize) and (x.Size() = N) and
    (mean.Size = N) and (variance.Size = N) and (mean_delta.size = N) and
    (variance_delta.size() = N), '[normalizeDelta] Tensor sizes must be aligned.');
  batchSize := blockSize * Delta.groups;
  for j := 0 to Delta.groups - 1 do
    for i := 0 to N - 1 do
      for k := 0 to blockSize - 1 do
      begin
        index := (i + j * N) * blockSize + k + offset;
        Delta.Data[index] :=
          Delta.Data[index] * 1 / (sqrt(variance.Data[i] + 0.00001)) + 2 *
          (variance_delta.Data[i] * (x.Data[index] - mean.Data[i]) + mean_delta.Data[i]) /
          batchSize;
      end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opNormalizeDelta)
  {$endif}
end;

procedure TTensor<T>.blockNormalize(const aMean, aStdDev: TTensor<T>;
  const blockSize: SizeInt);
var
  i, j, N: SizeInt;
begin
  N := aMean.Size();
  assert(aMean.Size() = aStdDev.Size(),
    'NORMALIZE : [Mean] and [StdDev] Tensor sizes do not match');
  assert(Groups * N * blockSize = Size(),
    'NORMALIZE : Tensor Size does not match [Batch X aMean] size');
  for i := 0 to Groups - 1 do
    normblkvv(N, aMean.Data, 1, aStdDev.Data, 1, Data + i * blockSize * N, blockSize);
end;

function TTensor<T>.Area(): SizeInt;
var i:SizeInt;
begin
  i := high(FShape);
  if i<0 then exit(0);
  case i+1 of
    1: Result := FShape[i];
    else
      Result := FShape[i - 1] * FShape[i]
  end;
end;

function TTensor<T>.Volume(): SizeInt;
var i:SizeInt;
begin
  i := high(FShape);
  if i<0 then exit(0);
  case i+1 of
    1: Result := FShape[i];
    2: Result := FShape[i-1] * FShape[i];
  else
    Result := FShape[i-2] * FShape[i-1] * FShape[i];
  end;
end;

class procedure TTensor<T>.Permute(var dst: TTensor<T>; const src: TTensor<T>;
  const newShape, Indecies, newIndecies, newArrange: TSizes; const lvl: SizeInt);
var
  i: SizeInt;
begin
  for i := 0 to src.FShape[lvl] - 1 do
  begin
    indecies[lvl] := i;
    newIndecies[newArrange[lvl]] := i;
    if lvl < high(src.FShape) then
      Permute(dst, src, newShape, Indecies, newIndecies, newArrange, lvl + 1)
    else
      dst.Data[dst.getIndex(newIndecies)] := src.Data[src.getIndex(indecies)];
  end;
end;

function TTensor<T>.Sum(const stride: SizeInt; N: SizeInt): T;
var
  i: SizeInt;
begin
  if not assigned(sumv) then sumv := TTensor<T>.Sum;
  if N=0 then N := Size();
  Result := sumv(N div stride, Data, stride);
end;

procedure TTensor<T>.Sums(const dst: PT; groups: SizeInt;
  const activation: TUnaryPFunc; const _data: PT);
begin
  if groups = 0 then groups := groups;
  Sums(Size(), Data, groups, dst, activation, _data);
end;

function TTensor<T>.mean(const stride: SizeInt; N: SizeInt): T;
begin
  if N=0 then N:=Size();
  Result := Division(self.sum(stride, N), CastI(N div stride));
end;

procedure TTensor<T>.MeansAndVars(aMeans, aVars: TTensor<T>;
  const offset: SizeInt; aSize: SizeInt);
var
  idx, i, b, N, blockSize: SizeInt;
  S, S2, m, v: T;
  D: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opMeansVars);
  {$endif}
  N := aMeans.Size();
  Assert(N = aVars.Size(),
    '[MeanAndVar]: Mean and Variance tensors must have the same size');
  if aSize=0 then
    aSize := Size();
  assert(offset + aSize <= Size());

  blockSize := aSize div (N * Groups);
  assert(aSize = N * Groups * blockSize, 'Tensor sizes doesn''t align');
  if not assigned(sumv) then
    sumv := TTensor<T>.sum;
  if not assigned(rssv) then
    rssv := TTensor<T>.rss;

  S := CastI(Groups * blockSize);
  S2 := CastI(Groups * blockSize - 1);
  D := Data + offset;
  for i := 0 to N - 1 do
  begin
    m := Default(T);
    v := Default(T);
    for b := 0 to groups - 1 do
    begin
      idx := (i + b * N) * blockSize;
      m := plus(m, sumv(blockSize, D + idx, 1));
    end;
    m := Division(m, S);
    aMeans.Data[i] := m;
    for b := 0 to groups - 1 do
    begin
      idx := (i + b * N) * blockSize;
      v := plus(v, rssv(blockSize, m, D + idx, 1));
    end;
    aVars.Data[i] := Division(v, S2);
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opMeansVars);
  {$endif}
end;

function TTensor<T>.Variance(const stride: SizeInt; N: SizeInt): T;
var
  mea: T;
  i: SizeInt;
begin
  if not assigned(varv) then varv := TTensor<T>.Variance;
  if N= 0 then N := Size();
  mea := Mean(stride);
  Result := varv(N div stride, mea, Data, stride);
end;

function TTensor<T>.stdDev(const stride: SizeInt; N: SizeInt): T;
begin
  if N = 0 then N := Size();
  Result := sqrt(Variance(stride, N));
end;

procedure TTensor<T>.MeanAndVar(var aMean, aVar: T; const stride: SizeInt;
  N: SizeInt);
var
  mea: T;
  i: SizeInt;
begin
  if not assigned(varv) then
    varv := TTensor<T>.Variance;
  if N=0 then N:=Size();
  aMean := Mean(stride, N);
  aVar := varv(N, aMean, Data, stride);
end;

class function TTensor<T>.subPrint(const src: TTensor<T>; const Indecies: TSizes;
  const lvl: SizeInt): string;
var
  i: SizeInt;
var
  s: string;
begin
  if not assigned(toStr) then toStr := _str;
  if not assigned(src.FShape) then exit('');
  Result := '';
  if lvl < High(src.FShape) then
  begin
    for i := 0 to src.FShape[lvl] - 1 do
    begin
      indecies[lvl] := i;
      Result := Result + sSeparator + subPrint(src, indecies, lvl + 1);
    end;
  end
  else
  begin
    for i := 0 to src.FShape[lvl] - 1 do
    begin
      indecies[lvl] := i;
      s := toStr(src.Data[src.getIndex(indecies)]);
      Result := Result + sSeparator + s;
    end;
  end;
  Delete(Result, 1, 1);
  Result := '[' + Result + ']' + sLineBreak;
end;

class function TTensor<T>.Sum(const N: SizeInt; const src: PT; const stride: SizeInt): T;
var
  i: SizeInt;
begin
  Result := src[0];
  for i := 1 to N - 1 do
    Result := Plus(Result, src[i * stride]);
end;

class procedure TTensor<T>.Sums(const N: SizeInt; const src: PT;
  const groups: SizeInt; const dst: PT; const func: TUnaryPFunc; const Data: PT);
var
  i, j, step: SizeInt;
  D: PT;
begin
  assert(assigned(addvv));
  step := N div groups;
  D := dst;
  if assigned(func) then
    for i := 0 to groups - 1 do
      for j := 0 to step - 1 do
        D[j] := plus(dst[j], func(src[i * step + j], j, Data))
  else
    for i := 0 to groups - 1 do
      addvv(step, src + i * step, 1, dst, 1, dst, 1);
end;

class function TTensor<T>.Dot(N: SizeInt; src1: PT; stride1: SizeInt;
  src2: PT; stride2: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := Plus(Result, Times(src1[i * stride1], src2[i * stride2]));
end;

class function TTensor<T>.sumSqrDiff(const N: SizeInt; const src1: PT;
  const stride1: SizeInt; const src2: PT; const stride2: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := Plus(Result, sqr(minus(src1[i * stride1], src2[i * stride2])));
end;

class function TTensor<T>.sumSqrDiff(const N: SizeInt; const src1: T;
  const src2: PT; const stride2: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := Plus(Result, sqr(minus(src2[i * stride2], src1)));
end;

class function TTensor<T>.sumAbsDiff(const N: SizeInt; const src1: PT;
  const stride1: SizeInt; const src2: PT; const stride2: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := Plus(Result, __abs(minus(src1[i * stride1], src2[i * stride2])));
end;

class function TTensor<T>.sumAbsDiff(const N: SizeInt; const src1: T;
  const src2: PT; const stride2: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := Plus(Result, __abs(minus(src2[i * stride2], src1)));
end;

class function TTensor<T>.Variance(const N: SizeInt; const mean: T;
  const src: PT; const stride: SizeInt): T;
var
  i: SizeInt;
  v : T;
begin
  Result := Default(T);
  for i := 0 to N - 1 do begin
    v := Minus(src[i * stride], mean);
    Result := Plus(Result, times(v, v));
  end;
  Result := Division(Result, CastI(N - 1));
end;

class function TTensor<T>.sumSqr(const n: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := plus(Result, Times(src[i * stride], src[i * stride]));
end;

class function TTensor<T>.sumAbs(const n: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := plus(Result, __abs(src[i * stride]));
end;

class function TTensor<T>.RSS(const N: SizeInt; const mean: T;
  const src: PT; const stride: SizeInt): T;
var
  i: SizeInt;
begin
  Result := Default(T);
  for i := 0 to N - 1 do
    Result := plus(Result, sqr(minus(src[i * stride], mean)));
end;

class procedure TTensor<T>.axpy(const N: SizeInt; const a: T;
  const X: PT; const INCX: SizeInt; const Y: PT; const INCY: SizeInt);
var
  i: SizeInt;
  O: PT;
begin
  for i := 0 to N - 1 do
  begin
    O := Y + i * INCY;
    O^ := Plus(Times(a, X[i * INCX]), O^);
  end;
end;

class function TTensor<T>.__max(const N: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  Result := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], Result) > 0 then
      Result := src[i * stride];
end;

class function TTensor<T>.__min(const N: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  Result := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], Result) < 0 then
      Result := src[i * stride];
end;

class procedure TTensor<T>.__max(const N: SizeInt; const src1: PT;
  const stride1: SizeInt; const src2: PT; const stride2: SizeInt;
  const dst: PT; const dstStride: SizeInt);
var
  i: SizeInt;
  D: PT;
begin
  //if not assigned(compare) then compare := _compare;
  D := dst;
  for i := 0 to N - 1 do
    if Compare(src1[i * stride1], src2[i * stride2]) > 0 then
      D[i * dstStride] := src1[i * stride1]
    else
      D[i * dstStride] := src2[i * stride2];
end;

class procedure TTensor<T>.__min(const N: SizeInt; const src1: PT;
  const stride1: SizeInt; const src2: PT; const stride2: SizeInt;
  const dst: PT; const dstStride: SizeInt);
var
  i: SizeInt;
  D: PT;
begin
  //if not assigned(compare) then compare := _compare;
  D := dst;
  for i := 0 to N - 1 do
    if Compare(src1[i * stride1], src2[i * stride2]) < 0 then
      D[i * dstStride] := src1[i * stride1]
    else
      D[i * dstStride] := src2[i * stride2];
end;

class procedure TTensor<T>.__max(const N: SizeInt; const a: T;
  const src1: PT; const stride1: SizeInt);
var
  i: SizeInt;
  O: PT;
begin
  //if not assigned(compare) then compare := _compare;
  for i := 0 to N - 1 do
  begin
    O := src1 + i * stride1;
    if compare(a, O^) > 0 then
      O^ := a;
  end;
end;

class procedure TTensor<T>.__min(const N: SizeInt; const a: T;
  const src1: PT; const stride1: SizeInt);
var
  i: SizeInt;
  O: PT;
begin
  //if not assigned(compare) then compare := _compare;
  for i := 0 to N - 1 do
  begin
    O := src1 + i * stride1;
    if compare(a, O^) < 0 then
      O^ := a;
  end;
end;

class procedure TTensor<T>.__maxs(const N: SizeInt; const src: PT;
  const groups: SizeInt; const dst: PT);
var
  i, j, step: SizeInt;
begin
  if not assigned(maxvv) then maxvv := __max;
  step := N div groups;
  for i := 0 to groups - 1 do
    maxvv(step, src + i * step, 1, dst, 1, dst, 1);
end;

class procedure TTensor<T>.__mins(const N: SizeInt; const src: PT;
  const groups: SizeInt; const dst: PT);
var
  i, j, step: SizeInt;
begin
  if not assigned(minvv) then minvv := __min;
  step := N div groups;
  for i := 0 to groups - 1 do
    minvv(step, src + i * step, 1, dst, 1, dst, 1);
end;

class procedure TTensor<T>.minMax(const N: SizeInt; const src: PT;
  const stride: SizeInt; var outMin, outMax: T; var outArgMin, outArgMax: SizeInt);
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  if N = 0 then exit;
  outMin := src[0];
  outMax := outMin;
  outArgMin := 0;
  outArgMax := 0;
  for i := 1 to N - 1 do
  begin
    if compare(src[i * stride], outMax) > 0 then
    begin
      outMax := src[i * stride];
      outArgMax := i;
    end;
    if compare(src[i * stride], outMin) < 0 then
    begin
      outMin := src[i * stride];
      outArgMin := i;
    end;
  end;
end;

class procedure TTensor<T>.minMax(const N: SizeInt; const src: PT;
  const stride: SizeInt; var outMin, outMax: T);
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  if N = 0 then exit;
  outMin := src[0];
  outMax := outMin;
  for i := 1 to N - 1 do
  begin
    if compare(src[i * stride], outMax) > 0 then
      outMax := src[i * stride];
    if compare(src[i * stride], outMin) < 0 then
      outMin := src[i * stride];
  end;
end;

class function TTensor<T>.argMin(const N: SizeInt; const src: PT;
  const stride: SizeInt): SizeInt;
var
  i: SizeInt;
  v: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], v) < 0 then
    begin
      v := src[i * stride];
      Result := i;
    end;
end;

class function TTensor<T>.argMax(const N: SizeInt; const src: PT;
  const stride: SizeInt): SizeInt;
var
  i: SizeInt;
  v: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], v) > 0 then
    begin
      v := src[i * stride];
      Result := i;
    end;
end;

class function TTensor<T>.minAbs(const N: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
  m: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := __abs(src[0]);
  for i := 1 to N - 1 do
  begin
    m := __abs(src[i * stride]);
    if Compare(m, Result) < 0 then
      Result := m;
  end;
end;

class function TTensor<T>.maxAbs(const N: SizeInt; const src: PT;
  const stride: SizeInt): T;
var
  i: SizeInt;
  m: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := __abs(src[0]);
  for i := 1 to N - 1 do
  begin
    m := __abs(src[i * stride]);
    if Compare(m, Result) > 0 then
      Result := m;
  end;
end;

class function TTensor<T>.argMinAbs(const N: SizeInt; const src: PT;
  const stride: SizeInt): SizeInt;
var
  i: SizeInt;
  v, e: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
  begin
    e := __abs(src[i * stride]);
    if Compare(e, v) < 0 then
    begin
      v := e;
      Result := i;
    end;
  end;
end;

class function TTensor<T>.argMaxAbs(const N: SizeInt; const src: PT;
  const stride: SizeInt): SizeInt;
var
  i: SizeInt;
  v, e: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
  begin
    e := __abs(src[i * stride]);
    if Compare(e, v) > 0 then
    begin
      v := e;
      Result := i;
    end;
  end;
end;

class function TTensor<T>.argMin(const N: SizeInt; const src: PT;
  const stride: int32): int32;
var
  i: int32;
  v: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], v) < 0 then
    begin
      v := src[i * stride];
      Result := i;
    end;
end;

class function TTensor<T>.argMax(const N: SizeInt; const src: PT;
  const stride: int32): int32;
var
  i: int32;
  v: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], v) > 0 then
    begin
      v := src[i * stride];
      Result := i;
    end;
end;

class function TTensor<T>.argAbsMin(const N: SizeInt; const src: PT;
  const stride: int32): int32;
var
  i: int32;
  v, e: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
  begin
    e := __abs(src[i * stride]);
    if Compare(e, v) < 0 then
    begin
      v := e;
      Result := i;
    end;
  end;
end;

class function TTensor<T>.argAbsMax(const N: SizeInt; const src: PT;
  const stride: int32): int32;
var
  i: int32;
  v: T;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  v := src[0];
  for i := 1 to N - 1 do
    if Compare(src[i * stride], v) > 0 then
    begin
      v := src[i * stride];
      Result := i;
    end;
end;

class function TTensor<T>.threshold(const N: SizeInt; var src: PT;
  const stride: SizeInt; const thresh: T; const ifAbove: PT;
  const ifEqualOrBelow: PT): SizeInt;
var
  i: SizeInt;
begin
  Result := 0;
  if assigned(ifAbove) and assigned(ifEqualOrBelow) then
  begin
    for i := 0 to N - 1 do
      if compare(src[i * stride], thresh) > 0 then
      begin
        src[i * stride] := ifAbove^;
        Inc(Result);
      end
      else
        src[i * stride] := ifEqualOrBelow^;
    exit;
  end;
  if assigned(ifAbove) then
  begin
    for i := 0 to N - 1 do
      if compare(src[i * stride], thresh) > 0 then
      begin
        src[i * stride] := ifAbove^;
        Inc(Result);
      end;
    exit;
  end;
  if assigned(ifEqualOrBelow) then
    for i := 0 to N - 1 do
      if compare(src[i * stride], thresh) < 0 then
      begin
        src[i * stride] := ifEqualOrBelow^;
        Inc(Result);
      end;

end;

class function TTensor<T>.absThreshold(const N: SizeInt; var src: PT;
  const stride: SizeInt; const thresh: T; const ifAbove: PT;
  const ifEqualOrBelow: PT): SizeInt;
var
  i: SizeInt;
begin
  Result := 0;
  if assigned(ifAbove) and assigned(ifEqualOrBelow) then
  begin
    for i := 0 to N - 1 do
      if compare(__abs(src[i * stride]), thresh) > 0 then
      begin
        src[i * stride] := ifAbove^;
        Inc(Result);
      end
      else
        src[i * stride] := ifEqualOrBelow^;
    exit;
  end;
  if assigned(ifAbove) then
  begin
    for i := 0 to N - 1 do
      if compare(__abs(src[i * stride]), thresh) > 0 then
      begin
        src[i * stride] := ifAbove^;
        Inc(Result);
      end;
    exit;
  end;
  if assigned(ifEqualOrBelow) then
    for i := 0 to N - 1 do
      if compare(__abs(src[i * stride]), thresh) < 0 then
      begin
        src[i * stride] := ifEqualOrBelow^;
        Inc(Result);
      end;

end;

class function TTensor<T>.countMatch(const N: SizeInt; const src1: PT;
  const stride1: SizeInt; const src2: PT; const stride2: SizeInt): SizeInt;
var
  i: SizeInt;
begin
  //if not assigned(compare) then compare := _compare;
  Result := 0;
  for i := 0 to N - 1 do
    Result := Result + Ord(compare(src1[i * stride1], src2[i * stride2]) = 0);
end;

class function TTensor<T>.countNotValue(const N: SizeInt; const val: T;  const src: PT; const stride: SizeInt): SizeInt;
var
  i: SizeInt;
begin
  Result := 0;
  for i := 0 to N - 1 do
    if src[i * stride] <> Val then
      Inc(Result);
end;

class function TTensor<T>.countValue(const N: SizeInt; const val: T;  const src: PT; const stride: SizeInt): SizeInt;
var
  i: SizeInt;
begin
  Result := 0;
  for i := 0 to N - 1 do
    if src[i * stride] = Val then
      Inc(Result);
end;

procedure TTensor<T>.AssignTo(var dst: TTensor<T>);
begin
  Dst.Data := Data;
  Dst.Groups := Groups;
  Dst.FShape := FShape;
  Dst.FDimSizes := FDimSizes;
  Dst.FStrides := FStrides;
  Dst.DynData := DynData;
end;

class function TTensor<T>.product(const e: TSizes): SizeInt;
var
  i: SizeInt;
begin
  if length(e) = 0 then exit(0);
  Result := e[0];
  for i := 1 to High(e) do
    Result := Result * e[i];
end;

class function TTensor<T>.product(const N: SizeInt; const e: PSizeInt): SizeInt;
var
  i: SizeInt;
begin
  if not assigned(e) then exit(0);
  Result := e[0];
  for i := 1 to N-1 do
    Result := Result * e[i];
end;

function TTensor<T>.similarity(const src: PT): double;
begin
  Result := countMatch(Size(), Data, 1, src, 1) / Size();
end;

function TTensor<T>.cosineSimilarity(src: PT): T;
var
  mul, d_a, d_b: T;
  divider: T;
begin
  //mul := 0.0; d_a := 0.0; d_b := 0.0;
  //for i := 0 to size() -1 do
  //    begin
  //        mul := mul + (Data[i] * src[i]);
  //        d_a := d_a + (Data[i] * Data[i]);
  //        d_b := d_b + (src[i] * src[i])
  //    end;

  mul := dot(src);
  if not assigned(sumsqrv) then
    sumsqrv := sumSqr;
  d_a := sumSqrv(Size(), Data, 1);
  d_b := sumSqrv(Size(), src, 1);

  divider := times(sqrt(d_a), sqrt(d_b));
  if compare(divider, zero) > 0 then
    exit(division(mul, divider));
  Result := zero;
end;

function TTensor<T>.w(): SizeInt;
begin
  Result := FShape[high(FShape)];
end;

function TTensor<T>.h(): SizeInt;
begin
  assert(length(FShape) > 0, 'Tensor must have two dimensions at least!');
  Result := FShape[high(FShape) - 1];
end;

function TTensor<T>.c(): SizeInt;
begin
  assert(length(FShape) > 2, 'Tensor must have three dimensions at least!');
  Result := FShape[high(FShape) - 2];
end;

function TTensor<T>.n(): SizeInt;
begin
  assert(length(FShape) > 3, 'Tensor must have four dimensions at least!');
  Result := FShape[high(FShape) - 3];
end;

function TTensor<T>.MSE(const vector: pointer; N: SizeInt): T;
var
  i: SizeInt;
  p: PT absolute vector;
  diff: T;
begin
  diff := Default(T);
  for i := 0 to N - 1 do
    diff := Plus(diff, sqr(Minus(Data[i], p[i])));
  Result := Division(diff, CastI(N));
end;

function TTensor<T>.min(const stride: SizeInt): T;
begin
  if not Assigned(minv) then minv := __min;
  Result := minv(Size() div stride, Data, stride);
end;

function TTensor<T>.max(const stride: SizeInt): T;
begin
  if not Assigned(maxv) then maxv := __max;
  Result := maxv(Size() div stride, Data, stride);
end;

procedure TTensor<T>.min(const val: T);
begin
  if not assigned(minvs) then minvs := __min;
  minvs(Size(), val, Data, 1);
end;

procedure TTensor<T>.max(const val: T);
begin
  if not assigned(maxvs) then maxvs := __max;
  maxvs(Size(), val, Data, 1);
end;

procedure TTensor<T>.min(const tensor: TTensor<T>);
begin
  if not assigned(minvv) then minvv := __min;
  minvv(Size, Data, 1, tensor.Data, 1, Data, 1);
end;

procedure TTensor<T>.max(const tensor: TTensor<T>);
begin
  if not assigned(maxvv) then maxvv := __max;
  maxvv(Size, Data, 1, tensor.Data, 1, Data, 1);
end;

procedure TTensor<T>.mins(const dst: PT; groups: SizeInt);
begin
  if groups = 0 then
    groups := groups;
  __mins(Size(), Data, groups, dst);
end;

procedure TTensor<T>.maxs(const dst: PT; groups: SizeInt);
begin
  if groups = 0 then
    groups := groups;
  __maxs(Size(), Data, groups, dst);
end;

procedure TTensor<T>.minMax(var outMin, outMax: T; var outArgMin, outArgMax: SizeInt;
  const stride: SizeInt; N:SizeInt = 0);
begin
  if not assigned(minmaxvsi) then minmaxvsi := minMax;
  if N=0 then N := Size();
  minmaxvsi(N, Data, stride, outMin, outMax, outArgMin, outArgMax);
end;

procedure TTensor<T>.sin(const dst: PT; const stride: SizeInt; const dstStride: SizeInt);
begin
  assert(assigned(sinv), 'Operation Not Implemented');
  sinv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.cos(const dst: PT; const stride: SizeInt; const dstStride: SizeInt);
begin
  assert(assigned(cosv), 'Operation Not Implemented');
  cosv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.tan(const dst: PT; const stride: SizeInt; const dstStride: SizeInt);
begin
  assert(assigned(tanv), 'Operation Not Implemented');
  tanv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.cotan(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(cotanv), 'Operation Not Implemented');
  cotanv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.tanH(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(tanHv), 'Operation Not Implemented');
  tanHv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcSin(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcSinv), 'Operation Not Implemented');
  arcSinv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcCos(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcCosv), 'Operation Not Implemented');
  arcCosv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcTan(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcTanv), 'Operation Not Implemented');
  arcTanv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcSinH(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcSinHv), 'Operation Not Implemented');
  arcSinHv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcCosH(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcCosHv), 'Operation Not Implemented');
  arcCosHv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.arcTanH(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(arcTanHv), 'Operation Not Implemented');
  arcTanHv(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.log10(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(log10v), 'Operation Not Implemented');
  log10v(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.log2(const dst: PT; const stride: SizeInt;
  const dstStride: SizeInt);
begin
  assert(assigned(log2v), 'Operation Not Implemented');
  log2v(size() div stride, Data, stride, dst, dstStride);
end;

procedure TTensor<T>.addGaussianNoise(const aStdDev: T);
var
  i: SizeInt;
begin
  for i := 0 to Size() - 1 do
    Data[i] := self.RandG(Data[i], aStdDev);
end;

procedure TTensor<T>.addUniformNoise(const aErr: T);
var
  i: SizeInt;
  r: T;
begin
  r := plus(aErr, aErr);
  for i := 0 to Size() - 1 do
    Data[i] := plus(minus(Data[i], aErr), rand(r));
end;

procedure TTensor<T>.Clamp(const aMin, aMax: T; const dst: PT);
var
  i: sizeInt;
  D: PT;
begin
  //if not assigned(compare) then compare := _compare;
  if not assigned(dst) then
    D := Data
  else
    D := dst;
  for i := 0 to Size() - 1 do
  begin
    D[i] := Data[i];
    if Compare(D[i], aMin) < 0 then
      D[i] := aMin;
    if Compare(D[i], aMax) > 0 then
      D[i] := aMax;
  end;
end;

function TTensor<T>.argMin(const stride: SizeInt): SizeInt;
begin
  if not Assigned(argMinv) then argMinv := argMin;
  if size() = 0 then exit(-1);
  Result := argMinv(Size() div stride, Data, stride);
end;

function TTensor<T>.argMax(const stride: SizeInt): SizeInt;
begin
  if not Assigned(argMaxv) then argMaxv := argMax;
  if size() = 0 then exit(-1);
  Result := argMaxv(Size() div stride, Data, stride);
end;

procedure TTensor<T>.argMin(const dst: PInt64);
var
  i, N: SizeInt;
begin
  if not Assigned(argMinv) then argMinv := argMin;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMinv(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMax(const dst: PInt64);
var
  i, N: SizeInt;
begin
  if not Assigned(argMaxv) then argMaxv := argMax;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMaxv(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMinAbs(const dst: PInt64);
var
  i, N: SizeInt;
begin
  if not Assigned(argMinAbsv) then argMinAbsv := argMinAbs;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMinAbsv(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMaxAbs(const dst: PInt64);
var
  i, N: SizeInt;
begin
  if not Assigned(argMaxAbsv) then argMaxAbsv := argMaxAbs;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMaxAbsv(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMin(const dst: PInt32);
var
  i, N: SizeInt;
begin
  if not Assigned(argMinv32) then argMinv32 := argMin;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMinv32(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMax(const dst: PInt32);
var
  i, N: SizeInt;
begin
  if not Assigned(argMaxv32) then argMaxv32 := argMax;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMaxv32(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMinAbs(const dst: PInt32);
var
  i, N: SizeInt;
begin
  if not Assigned(argMinAbsv32) then argMinAbsv32 := argAbsMin;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMinAbsv32(N, Data + i * N, 1);
end;

procedure TTensor<T>.argMaxAbs(const dst: PInt32);
var
  i, N: SizeInt;
begin
  if not Assigned(argMaxAbsv32) then argMaxAbsv32 := argAbsMax;
  if size() = 0 then exit;
  N := Size() div Groups;
  for i := 0 to Groups - 1 do
    dst[i] := argMaxAbsv32(N, Data + i * N, 1);
end;

function TTensor<T>.minAbs(const stride: SizeInt): T;
begin
  if not Assigned(minAbsv) then minAbsv := minabs;
  Result := minAbsv(Size() div stride, Data, stride);
end;

function TTensor<T>.maxAbs(const stride: SizeInt): T;
begin
  if not Assigned(maxAbsv) then maxAbsv := maxabs;
  Result := maxAbsv(Size() div stride, Data, stride);
end;

procedure TTensor<T>.axpy(const a: T; const x: PT; N: SizeInt;
  const offset: SizeInt; dstStride: SizeInt; xStride: SizeInt);
var
  i: SizeInt;
var
  d: PT;
begin
  if N < 0 then
    N := (Size() - offset) div dstStride;

  d := Data + offset;

  if not assigned(axpysvv) then axpysvv := axpy;

  axpysvv(N, a, x, xStride, d, dstStride);
end;

class procedure TTensor<T>.map(const func: TMapFunc<T>; const src: TTensor<T>;
  var dst: TTensor<T>);
var
  i, NDst, N: SizeInt;
  dstBatch: boolean;
begin
  NDst := dst.Size();
  N := src.Size();
  assert(Ndst >= N, '[map] : destination size must be greater or equal than source size.');
  for i := 0 to NDst - 1 do
    dst.Data[i] := func(src.Data[i mod N], i mod N);
end;

class procedure TTensor<T>.map(const func: TMapFuncLambda<T>;
  const src: TTensor<T>; var dst: TTensor<T>);
var
  i, NDst, N: SizeInt;
  dstBatch: boolean;
begin
  NDst := dst.Size();
  N := src.Size();
  assert(Ndst >= N, '[map] : destination size must be greater or equal than source size.');
  for i := 0 to NDst - 1 do
    dst.Data[i] := func(src.Data[i mod N], i mod N);
end;

class function TTensor<T>.reduce(const func: TReduceProc<T, PT>;
  const src: PT; const N, stride: SizeInt; const start: T): T;
var
  i: SizeInt;
begin
  Result := start;
  for i := 0 to N - 1 do
    Result := func(Result, src[i * stride], i, src, N);
end;

class function TTensor<T>.reduce(const func: TReduceProcLambda<T, PT>;
  const src: PT; const N, stride: SizeInt; const start: T): T;
var
  i: SizeInt;
begin
  Result := start;
  for i := 0 to N - 1 do
    Result := func(Result, src[i * stride], i, src, N);
end;

class function TTensor<T>.reduce(const func: TReduceProc<T, PT>;
  const src: PT; const N: SizeInt; const stride: SizeInt): T;
var
  i: SizeInt;
begin
  assert(N > 0);
  Result := src[0];
  for i := 1 to N - 1 do
    Result := func(Result, src[i * stride], i, src, N);
end;

class function TTensor<T>.reduce(const func: TReduceProcLambda<T, PT>;
  const src: PT; const N: SizeInt; const stride: SizeInt): T;
var
  i: SizeInt;
begin
  assert(N > 0);
  Result := src[0];
  for i := 1 to N - 1 do
    Result := func(Result, src[i * stride], i, src, N);
end;

procedure TTensor<T>.LerpValues(const _min, _max, _min2, _max2: T);
var
  r: T;
  i: SizeInt;
begin
  r := Division(Minus(_max2, _min2), Minus(_max, _min));
  for i := 0 to Size() - 1 do
    Data[i] := Plus(_min2, Times(r, Minus(Data[i], _min)));
end;

function TTensor<T>.countNotValue(const src: T; const stride: SizeInt): SizeInt;
begin
  Result := countNotValue(Size() div stride, src, Data, stride);
end;

function TTensor<T>.countValue(const src: T; const stride: SizeInt): SizeInt;
var
  i: SizeInt;
begin
  Result := countValue(size() div stride, src, Data, stride)
end;

function TTensor<T>.findValues(const N: SizeInt; const values: PT): TArray<SizeInt>;
var i, j, k:SizeInt;
begin
  assert(values<>nil);
  setLength(result, Size());
  k:=0;
  for i:=0 to Size()-1 do
    for j:=0 to N-1 do
      if Data[i] = values[j] then begin
        result[k] := i;
        inc(k)
      end;
  setLength(result, k)
end;

function TTensor<T>.findValues(const values: TArray<T>): TArray<SizeInt>;
begin
  result := findValues(length(values), pointer(values))
end;

procedure TTensor<T>.polynomial(const coef: TArray<T>);
begin
  //Horner's Method https://en.wikipedia.org/wiki/Horner%27s_method
  polynomial(Size, coef, Data, zero);

end;

procedure TTensor<T>.polynomial(const coef: TArray<T>; const aStdDev: T);
begin
  //Horner's Method https://en.wikipedia.org/wiki/Horner%27s_method
  polynomial(Size, coef, Data, aStdDev);
end;

procedure TTensor<T>.histogram(const aCount: SizeInt; var dst: PInteger;
  outMin: PT; outMax: PT);
var
  i: SizeInt;
begin
  if assigned(outMin) and assigned(outMax) then
    for i := 0 to groups - 1 do
      histogram(groupSize(), Data + i*groupSize(), aCount, dst + i*aCount, outMin + i, outMax + i)
  else
    for i := 0 to groups - 1 do
      histogram(groupSize(), Data + i*groupSize(), aCount, dst + i*aCount, nil, nil);
end;

function TTensor<T>.Histogram(const aCount: SizeInt; outMin: PT; outMax: PT): TArray<integer>;
begin
  assert(aCount > 0, 'aCount must be larger than zero');
  setLength(result, aCount * groups);
  histogram(aCount, PInteger(result), outMin, outMax);
end;

function ftos(f: double; prec: integer = 0): string;
begin
  str(f: 1: prec, Result);
end;

procedure _line(const x0, y0, x1, y1: integer; const color: longword;
  const d: TBitPixels);
var
  steep: boolean;
  dx, dy, sx, sy, xe, ye, x, y: integer;
begin
  dx := x1 - x0;
  dy := y1 - y0;
  steep := system.abs(dy) > system.abs(dx);
  sx := 1 - 2 * integer(x1 < x0);
  sy := 1 - 2 * integer(y1 < y0);
  if steep then
  begin
    y := 0;
    xe := 0;
    while y <> dy do
    begin
      x := x0 + round(y * dx / dy);
      d[y0 + y, x] := color;
      xe := x;
      Inc(y, sy);
    end;
  end
  else
  begin
    x := 0;
    ye := 0;
    while x <> dx do
    begin
      y := y0 + round(x * dy / dx);
      d[y, x0 + x] := color;
      ye := y;
      Inc(x, sx);
    end;
  end;
end;


function TTensor<T>.plot(const xAxis: TTensor<T>): TArray<SizeInt>;
const
  xLen: integer = 40;
  yLen: integer = 15;

  xTicks: integer = 4;
  yTicks: integer = 4;
  prec = 0.001;
const
  colors: array[0..4] of longword = ($ffcc00, $0088ff, $ff00ff, $0088ff, $ffff00);
  dots: array[0..255] of string = (
      ' ', '⠁', '⠂', '⠃', '⠄', '⠅', '⠆', '⠇', '⡀', '⡁', '⡂', '⡃', '⡄', '⡅', '⡆', '⡇'
    , '⠈', '⠉', '⠊', '⠋', '⠌', '⠍', '⠎', '⠏', '⡈', '⡉', '⡊', '⡋', '⡌', '⡍', '⡎', '⡏'
    , '⠐', '⠑', '⠒', '⠓', '⠔', '⠕', '⠖', '⠗', '⡐', '⡑', '⡒', '⡓', '⡔', '⡕', '⡖', '⡗'
    , '⠘', '⠙', '⠚', '⠛', '⠜', '⠝', '⠞', '⠟', '⡘', '⡙', '⡚', '⡛', '⡜', '⡝', '⡞', '⡟'
    , '⠠', '⠡', '⠢', '⠣', '⠤', '⠥', '⠦', '⠧', '⡠', '⡡', '⡢', '⡣', '⡤', '⡥', '⡦', '⡧'
    , '⠨', '⠩', '⠪', '⠫', '⠬', '⠭', '⠮', '⠯', '⡨', '⡩', '⡪', '⡫', '⡬', '⡭', '⡮', '⡯'
    , '⠰', '⠱', '⠲', '⠳', '⠴', '⠵', '⠶', '⠷', '⡰', '⡱', '⡲', '⡳', '⡴', '⡵', '⡶', '⡷'
    , '⠸', '⠹', '⠺', '⠻', '⠼', '⠽', '⠾', '⠿', '⡸', '⡹', '⡺', '⡻', '⡼', '⡽', '⡾', '⡿'
    , '⢀', '⢁', '⢂', '⢃', '⢄', '⢅', '⢆', '⢇', '⣀', '⣁', '⣂', '⣃', '⣄', '⣅', '⣆', '⣇'
    , '⢈', '⢉', '⢊', '⢋', '⢌', '⢍', '⢎', '⢏', '⣈', '⣉', '⣊', '⣋', '⣌', '⣍', '⣎', '⣏'
    , '⢐', '⢑', '⢒', '⢓', '⢔', '⢕', '⢖', '⢗', '⣐', '⣑', '⣒', '⣓', '⣔', '⣕', '⣖', '⣗'
    , '⢘', '⢙', '⢚', '⢛', '⢜', '⢝', '⢞', '⢟', '⣘', '⣙', '⣚', '⣛', '⣜', '⣝', '⣞', '⣟'
    , '⢠', '⢡', '⢢', '⢣', '⢤', '⢥', '⢦', '⢧', '⣠', '⣡', '⣢', '⣣', '⣤', '⣥', '⣦', '⣧'
    , '⢨', '⢩', '⢪', '⢫', '⢬', '⢭', '⢮', '⢯', '⣨', '⣩', '⣪', '⣫', '⣬', '⣭', '⣮', '⣯'
    , '⢰', '⢱', '⢲', '⢳', '⢴', '⢵', '⢶', '⢷', '⣰', '⣱', '⣲', '⣳', '⣴', '⣵', '⣶', '⣷'
    , '⢸', '⢹', '⢺', '⢻', '⢼', '⢽', '⢾', '⢿', '⣸', '⣹', '⣺', '⣻', '⣼', '⣽', '⣾', '⣿');
var
  bitpixels: TBitPixels;

  amin, amax: T;
  gData: PT;
  i, j, k, l, outArgMin, outArgMax, xTickLen, xTick, xPow, xPrec,
  yTickLen, yTick, yPow, yPrec, ow, oh: SizeInt;

  minxVal, maxxVal, minyVal, maxyVal, xStart, xRange, xTickStart,
  xTickInc, yStart, yRange, yTickStart, yTickInc, xVal1, xVal2, yVal1, yVal2: double;

  d, s, sp, yTickLeg, xTickLeg: string;

  a, v: array of string;
  x, y, xLen2, yLen2: integer;
  color: longword;
  c: byte;
begin

  if not assigned(Data) then exit;
  while yLen mod yTicks > 0 do
    Inc(yLen);
  //Write(#$1b'[', yLen + 6, 'S');   // scroll up #lines
  //Write(#$1b'[', yLen + 6, 'A');   // cursor up #lines
  ow:=0; oh:=0;
  if assigned(xAxis.Data) then
  begin
    minxVal := 0;
    maxxVal := 0;
    d := 'X Axis : ' + xAxis.TypeName() + ' Tensor (';
    for i := 0 to High(xAxis.Shape) do
      if i = 0 then d := d + IntToStr(xAxis.Shape[i])
      else
        d := d + ' X ' + IntToStr(xAxis.Shape[i]);
    d := d + ')';
    write(d, #$1B'[',length(d){-9},'D'#$1B'[B'); // note : indent to align under YAxis Titles  ?
    ow := math.max(ow, length(d)); inc(oh);
    //writeln(d);
    if minxVal = maxxVal then
    begin
      xAxis.minMax(amin, amax, outArgMin, outArgMax);
      vcvtd(1, @amin, @minxVal);
      vcvtd(1, @amax, @maxxVal);
      d := format('[min : %s @ %d, max : %s @ %d]',
        [toStr(amin), outArgMin, toStr(amax), outArgMax]);
      Write(d, #$1B'[', length(d), 'D'#$1B'[2B');
      ow := math.max(ow, length(d)); inc(oh,2);
      if minxVal = maxxVal then
        exit;
      //writeln(d)
    end;
  end
  else
  begin
    minxVal := 0;
    maxxVal := Size() div groups - 1;
  end;

  minyVal := 0;
  maxyVal := 0;
  d := 'Y Axis : ' + TypeName() + ' Tensor (';
  for i := 0 to High(Shape) do
    if i = 0 then d := d + IntToStr(Shape[i])
    else
      d := d + ' X ' + IntToStr(Shape[i]);
  d := d + ')';
  write(d, cursorMove(cmBackward, length(d)), cursorMove(cmDown)); // note :indent to align under YAxis Title  ?
  ow := math.max(ow, length(d)); inc(oh);
  //writeln(d);
  if minyVal = maxyVal then
  begin
    minMax(amin, amax, outArgMin, outArgMax);
    vcvtd(1, @amin, @minyVal);
    vcvtd(1, @amax, @maxyVal);
    d := format('[min : %s @ %d, max : %s @ %d]',
      [toStr(amin), outArgMin, toStr(amax), outArgMax]);
    Write(d, cursorMove(cmBackward, length(d)), cursorMove(cmDown, 2));
    ow := math.max(ow, length(d)); inc(oh,2);
    if minyVal = maxyVal then
      exit;
    //writeln(d)
  end;

  setLength(a, yLen + 1);
  setLength(v, yLen + 1);

  yStart := minyVal;
  yRange := maxyVal - yStart;
  yTickLen := ceil(yLen / yTicks);
  yTickInc := yRange / yTicks;
  yPow := Math.floor(Math.log10(yTickInc));
  yTickStart := yStart;
  if yPow <> -1 then
  begin
    yTickStart := yTickStart / Math.Power(10, yPow);
    yTickInc := yTickInc / Math.Power(10, yPow);
  end;
  yTickLeg := string.Create('0', system.abs(yPow));
  if yPow > -1 then
    yTickLeg := 'X1' + ytickleg +'   '
  else if yPow = -1 then
    yTickLeg := '      '
  else
    yTickLeg := 'X0.' + ytickleg + '1   ';
  yPrec := Ord(frac(yTickInc) > prec);

  i := 0;
  yTick := 0;
  while i < yLen do
  begin
    if i mod yTickLen = 0 then
    begin
      a[i] := ftos(yTickStart + yTick * yTickInc, yPrec);
      Inc(yTick);
    end
    else
    begin
      a[i] := '';
    end;
    Inc(i);
  end;
  a[i] := ftos(yTickStart + yTick * yTickInc, yPrec);
  Write(yTickLeg, cursorMove(cmBackward, length(yTickLeg) + 1), cursorMove(cmDown));
  ow := math.max(ow, length(yTickLeg)); inc(oh);

  //writeln(yTickLeg);

  while xLen mod xTicks > 0 do
    Inc(xLen);

  xStart := minXVal;
  xRange := maxxVal - xStart;
  xTickLen := ceil(xLen / xTicks);
  xTickInc := xRange / xTicks;
  xPow := Math.floor(Math.log10(xTickInc));
  xTickStart := xStart;
  if xPow <> -1 then
  begin
    xTickStart := xStart / Math.Power(10, xPow);
    xTickInc := xTickInc / Math.Power(10, xPow);
  end;
  xTickLeg := string.Create('0', xPow);
  if xPow > -1 then
    xTickLeg := 'X1' + xtickleg +'   '
  else if xPow = -1 then
    xTickLeg := '      '
  else
    xTickLeg := 'X0.' + xtickleg + '1   ';
  xPrec := Ord(frac(xTickInc) >= prec);

  s := '';
  i := 0;
  xTick := 0;
  while i <= xLen do
  begin
    if i mod xTickLen = 0 then
    begin
      s := s + '''' + ftos(xTickStart + xTick * xTickInc, xPrec);
      Inc(xTick);
    end
    else
    begin
      s := s + ' ';
    end;
    i := length(s);
  end;

  xLen2 := xLen * 2;
  yLen2 := yLen * 4;
  setLength(bitpixels, yLen2 + 4, xLen2 + 2);

  for l := 0 to groups - 1 do
  begin
    gData := Data + l * groupSize();
    //if xRange > xLen2 then
    ////if groupSize() > xLen2 then
    //  for i := 1 to xLen2 - 1 do
    //  begin
    //    //vcvtd(1, @gData[round(xStart + (xRange-1)*(i-1)/(xLen2))], @yVal2);
    //    //vcvtd(1, @gData[round(xStart + (xRange-1)*i    /(xLen2))], @yVal1);
    //    vcvtd(1, @gData[round((groupSize() - 1) * (i - 1) / xLen2)], @yVal2);
    //    vcvtd(1, @gData[round((groupSize() - 1) * i / xLen2)], @yVal1);
    //    _line(i - 1, round((yLen2) * (yVal2 - yStart) / yRange),
    //      i, round((yLen2) * (yVal1 - yStart) / yRange),
    //      colors[l mod length(colors)], bitpixels);
    //  end
    //else
    begin
      k := 0;
      //for i:= 1 to trunc(xRange)-1 do begin
      //j := trunc(i * xLen2 / xRange);
      //vcvtd(1, @gData[trunc(xStart + i)-1], @yVal2);
      //vcvtd(1, @gData[trunc(xStart + i)], @yVal1);
      for i := 1 to groupSize() - 1 do
      begin
        j := trunc(i * xLen2 / groupSize());
        vcvtd(1, @gData[i - 1], @yVal2);
        vcvtd(1, @gData[i], @yVal1);
        yVal1 := (yLen2) * (yVal1 - yStart) / yRange;
        yVal2 := (yLen2) * (yVal2 - yStart) / yRange;
        _line(k, round(yVal2), j, round(yVal1), colors[l mod length(colors)], bitPixels);
        k := j;
      end;
    end;
  end;

  for i := 0 to yLen do
  begin
    l := $8 + i * $20 div yLen;
    //v[i] := format(#$1B'[48;2;%d;%d;%dm', [trunc(l * 0.8), 0, l]);
    v[i] := setBackGray(4 * i div yLen);
    //v[i] := setBackColor(trunc(l * 0.8), 0, l);
    for j := 0 to xLen do
    begin
      k := 0;
      c := 0;
      color := 0;
      for x := 2 * j to j * 2 + 1 do
        for y := i * 4 + 3 downto i * 4 do
        begin
          if bitpixels[y, x] > 0 then
          begin
            color := color or bitpixels[y, x];
            c := c or 1 shl k;
          end;
          Inc(k);
        end;
      d := dots[c];
      if (d = ' ') then
      begin
        if (j + 2 > 0) {and (j + 2 < xLen)} and (s[j + 2] = '''') then
          d := setFaint + setColor4(colorSilver) +'¦' // ¦
        else if (a[i] <> '') and (d = ' ') then
          d := setFaint + setColor4(colorSilver) + 'ˍ';
      end
      else
        d := clearFaint + d;
      //v[i] := v[i] + format(#$1B'[38;2;%d;%d;%dm', [color and $ff,
      //  (color shr $8) and $ff, (col* shr $10) and $ff]) + d;
      v[i] := v[i] + setColor5(round(5*(color and $ff)/$ff), round(5*((color shr $8) and $ff/$ff)), round(5*((color shr $10) and $ff/$ff))) + d;
      //v[i] := v[i] + setColor(color and $ff, (color shr $8) and $ff, (color shr $10) and $ff) + d;

    end;
    v[i] := v[i] + clearFaint +  resetColor + resetBackColor;
  end;



  j := 0;
  for i := 0 to yLen do
    j := Math.max(length(a[i]), j);
  d := '';
  for i := yLen downto 0 do
  begin
    sp := string.Create(' ', j - length(a[i]));
    if a[i] = '' then
      d := sp + ' │' + v[i]
    else
      d := sp + a[i] + '_│' + v[i];
    Write(d, cursorMove(cmBackward, xLen + j + 3), cursorMove(cmDown));
    ow := math.max(ow, xLen + j + 3); inc(oh);
    //writeln(d);
  end;

  d := string.Create(' ', j + 1) + setOverline + S {+ ''''} + clearOverline {+
    ftos(xTickStart + xTick * xTickInc, xPrec)} + ' ' + xTickLeg;
  Write(d, cursorMove(cmBackward,length(d) - 10), cursorMove(cmDown, 2));
  ow := math.max(ow, length(d) - length(setOverline) - length(clearOverline)); inc(oh);
  result := [ow, oh];
  //writeLn(d)
end;

function TTensor<T>.plot: TArray<SizeInt>;
var
  x: TTensor<T>;
begin
  result := plot(X);
end;

function TTensor<T>.print(const consolePixel: TTensorPrintStyle; tile: SizeInt; minVal: double; maxVal: double): TArray<SizeInt>;
const
      csi =#$1B'[';
      up =#$1B'[A';
      dw =#$1B'[B';
      fw =#$1B'[C';
      bw =#$1B'[D';
      sc =#$1B'[s';
      rc =#$1B'[u';
      er =#$1B'[0K';
      cpos=#$1B'[6n';
var
  amin, amax: T;
  i, j, k, t, _w, _h, _c, _area, index, outArgMin, outArgMax, ow, oh: SizeInt;
  l: longword;
  range, r, g, b, r2, g2, b2: double;
  S: string;
const
  __shade: array[0..4] of string = (' ', '░', '▒', '▓', '█');  // delphi will complain if no string type defined, MacOS will type rubbish if string type is defined!! :(

  halfChar = '▀';
begin
  if not assigned(Data) then exit;
  S := TypeName() + ' Tensor (';
  for i := 0 to High(Shape) do
    if i = 0 then
      S := S + IntToStr(Shape[i])
    else begin
      S := S + ' X ';
      S := S + IntToStr(Shape[i])
    end;
  S := S +')';
  ow := length(S); oh :=1;
  write(S, csi, length(S), 'D', dw);
  //writeln(S);
  ow:=length(S); oh:=1;
  if consolePixel <> psValues then
  begin
    if minVal = maxVal then
    begin
      minMax(amin, amax, outArgMin, outArgMax);
      vcvtd(1, @amin, @minVal);
      vcvtd(1, @amax, @maxVal);
      S := '[min : '+ toStr(amin)+ '@'+ intToStr(outArgMin)+ ', max : '+
        toStr(amax)+ '@'+ intToStr(outArgMax)+ ']';
      write(S, csi, length(S), 'D', dw);
      //writeln(S);
      ow:=math.max(ow, length(S)); inc(oh);
    end;
    _w := w();
    if length(FShape) > 1 then
    begin
      _h := h;
      _area := _h * _w;
    end
    else
    begin
      _h := 1;
      _area := _w;
    end;
    _c := (1 + 2 * Ord(consolePixel in [psColor8, psColor24]));
    range := maxVal - minVal;
    result := [ow, oh];
    if (range < dEPSILON) or (tile < 1) then exit;
    S := '';
    l:=0;
    for i := 0 to size() div (_c * _area * tile) - 1 do
    begin
      for j := 0 to _h div (1 + Ord(consolePixel <> psGray5)) - 1 do
      begin
        for t := 0 to tile - 1 do
        begin
          for k := 0 to _w - 1 do
          begin
            index := i * _c * tile * _area + t * _c * _h * _w + j *
              (1 + Ord(consolePixel <> psGray5)) * _w + k;
            if index < size() then
            begin
              vcvtd(1, @Data[index], @r);
              case consolePixel of
                psGray5: S := S + __shade[round(4 * (r - minVal) / range)];
                psGray24:
                begin
                  Inc(index, _w);
                  vcvtd(1, @Data[index], @r2);
                  r := 232 + 23 * (r - minVal) / range;
                  r2 := 232 + 23 * (r2 - minVal) / range;
                  S := S + #$1B'[38;5;' + IntToStr(round(r)) + 'm'
                    + #$1B'[48;5;' + IntToStr(round(r2)) + 'm' + halfChar;
                end;
                psGray:
                begin
                  Inc(index, _w);
                  vcvtd(1, @Data[index], @r2);
                  r := $ff * (r - minVal) / range;
                  r2 := $ff * (r2 - minVal) / range;
                  S := S + #$1B'[38;2;' + IntToStr(round(r)) + ';' +
                    IntToStr(round(r)) + ';' + IntToStr(round(r)) + 'm' +
                    #$1B'[48;2;' + IntToStr(round(r2)) + ';' + IntToStr(round(r2)) + ';' + IntToStr(
                    round(r2)) + 'm' + halfChar;
                end;
                psColor8:
                begin
                  vcvtd(1, @Data[index + _area], @g);
                  vcvtd(1, @Data[index + _area * 2], @b);
                  // next line
                  Inc(index, _w);
                  vcvtd(1, @Data[index], @r2);
                  vcvtd(1, @Data[index + _area], @g2);
                  vcvtd(1, @Data[index + _area * 2], @b2);

                  r := 5 * (r - minVal) / range;
                  g := 5 * (g - minVal) / range;
                  b := 5 * (b - minVal) / range;

                  r2 := 5 * (r2 - minVal) / range;
                  g2 := 5 * (g2 - minVal) / range;
                  b2 := 5 * (b2 - minVal) / range;

                  S := S + #$1B'[38;5;' + IntToStr(16 + round(b) +
                    6 * round(g) + 36 * round(r)) + 'm' + #$1B'[48;5;' +
                    IntToStr(16 + round(b2) + 6 * round(g2) + 36 * round(r2)) + 'm' + halfChar;
                end;
                psColor24:
                begin
                  vcvtd(1, @Data[index + _area], @g);
                  vcvtd(1, @Data[index + _area * 2], @b);
                  // nex line
                  Inc(index, _w);
                  vcvtd(1, @Data[index], @r2);
                  vcvtd(1, @Data[index + _area], @g2);
                  vcvtd(1, @Data[index + _area * 2], @b2);

                  r := $ff * (r - minVal) / range;
                  g := $ff * (g - minVal) / range;
                  b := $ff * (b - minVal) / range;

                  r2 := $ff * (r2 - minVal) / range;
                  g2 := $ff * (g2 - minVal) / range;
                  b2 := $ff * (b2 - minVal) / range;

                  S := S + #$1B'[38;2;' + IntToStr(round(r)) + ';' +
                    IntToStr(round(g)) + ';' + IntToStr(round(b)) + 'm' +
                    #$1B'[48;2;' + IntToStr(round(r2)) + ';' + IntToStr(round(g2)) + ';' + IntToStr(
                    round(b2)) + 'm' + halfChar;
                end;

              end;
            end;
          end;
          //if consolePixel<>psGray5 then
          //  S := S + #$1B'[0m '
        end;
        write(S, csi, _w*tile, 'D' ,dw);
        //writeln(S);
        ow:=math.max(ow, _w*tile); inc(oh);
        inc(l);
        S := '';
      end;
    end;
    if consolePixel <> psGray5 then
      S := #$1B'[0m';
    write(S);
    //writeln(S);
    result := [ow, oh];
    exit;
  end;

  writeln(toString());
end;

procedure TTensor<T>.printStat(N: SizeInt);
var
  i, outArgMin, outArgMax: SizeInt;
  meanVal, stdVal, minVal, maxVal, magVal: T;
begin
  if not assigned(Data) then exit;
  if not assigned(sumsqrv) then sumsqrv := sumsqr;
  if N=0 then N:=Size();
  Write(TypeName(), ' Tensor (');
  for i := 0 to High(Shape) do
    if i = 0 then Write(Shape[i])
    else
      Write(' X ', Shape[i]);
  writeln(')');
  minMax(minVal, maxVal, outArgMin, outArgMax, 1, N);
  MeanAndVar(meanVal, stdVal, 1, N);
  magVal := self.sqrt(sumSqrv(N, Data, 1));
  stdVal := self.Sqrt(stdVal);
  //for i:=0 to Math.min(N,6)-1 do
  //  if i=0 then
  //    write('[ ', toStr(Data[i]))
  //  else
  //    write(', ',ToStr(Data[i]));
  //writeln(' ...]');
  writeLn('[min : ', toStr(minVal), ' @', outArgMin, ', max : ',
    toStr(maxVal), ' @', outArgMax, ', mean : ', toStr(meanVal), ', stdDev : ',
    toStr(stdVal), ', magnitude : ', toStr(magVal), ']');
end;

function TTensor<T>.print(const scale: single; const gray: boolean; const tile: SizeInt): TArray<SizeInt>;
const
      csi =#$1B'[';
      sup =#$1B'[S';
      sdw =#$1B'[T';
      up =#$1B'[A';
      dw =#$1B'[B';
      fw =#$1B'[C';
      bw =#$1B'[D';
      sc =#$1B'[s';
      rc =#$1B'[u';
      er =#$1B'[0K';
      cpos=#$1B'[6n';
var
  amin, amax: T;
  maxVal, minVal: double;
  i, j, k, t, _w, _h, _c, _area, index, outArgMin, outArgMax, ow, oh: SizeInt;
  range, r, g, b, r2, g2, b2: double;
  S: string;
const
  __shade: array[0..4] of shortstring = (' ', '░', '▒', '▓', '█');
  halfChar = '▀';
begin
  S := TypeName() + ' Tensor (';
  for i := 0 to High(Shape) do
    if i = 0 then
      S := S + IntToStr(Shape[i])
    else begin
      S := S + ' X ';
      S := S + IntToStr(Shape[i])
    end;
  S := S +')';
  write(sup, sLineBreak{S, csi, length(S), 'D', dw});
  ow:=length(S); oh := 1;
  minMax(amin, amax, outArgMin, outArgMax);
  vcvtd(1, @amin, @minVal);
  vcvtd(1, @amax, @maxVal);
  S := '[min : '+ toStr(amin)+ '@'+ intToStr(outArgMin)+ ', max : '+ toStr(amax)+  '@'+ intToStr(outArgMax)+ ']';
  write(sup, sLinebreak{S, csi, length(S), 'D', dw});
  ow:=math.max(ow, length(S)); inc(oh);
  _w := w();
  if length(FShape) > 1 then
  begin
    _h := h;
    _area := _h * _w;
  end
  else
  begin
    _h := 1;
    _area := _w;
  end;
  _c := (1 + 2 * Ord(not gray));
  range := maxVal - minVal;
  result := [ow, oh];
  if (range < dEPSILON) or (tile < 1) then exit;
  S := '';
  for i := 0 to size() div (_c * _area * tile) - 1 do
  begin
    for j := 0 to trunc(_h * scale / 2) - 1 do
    begin
      for t := 0 to tile - 1 do
      begin
        for k := 0 to trunc(_w * scale) - 1 do
        begin
          index := i * _c * tile * _area + round(t * _c * _h + j * 2 / scale) * _w + round(k / scale);
          if index < size() then
          begin
            vcvtd(1, @Data[index], @r);
            if gray then
            begin
              index := i * _c * tile * _area + round(t * _c * _h + (j * 2 + 1) / scale) * _w +
                round(k / scale);
              vcvtd(1, @Data[index], @r2);
              r := $ff * (r - minVal) / range;
              r2 := $ff * (r2 - minVal) / range;
              S := S + #$1B'[38;2;' + IntToStr(round(r)) + ';' + IntToStr(
                round(r)) + ';' + IntToStr(round(r)) + 'm' +
                #$1B'[48;2;' + IntToStr(round(r2)) + ';' + IntToStr(round(r2)) + ';' + IntToStr(
                round(r2)) + 'm' + halfChar;
            end
            else
            begin
              vcvtd(1, @Data[index + _area], @g);
              vcvtd(1, @Data[index + _area * 2], @b);
              // nex line
              index := i * _c * tile * _area + round(t * _c * _h + (j * 2 + 1) / scale) * _w + round(k / scale);
              vcvtd(1, @Data[index], @r2);
              vcvtd(1, @Data[index + _area], @g2);
              vcvtd(1, @Data[index + _area * 2], @b2);

              r := $ff * (r - minVal) / range;
              g := $ff * (g - minVal) / range;
              b := $ff * (b - minVal) / range;

              r2 := $ff * (r2 - minVal) / range;
              g2 := $ff * (g2 - minVal) / range;
              b2 := $ff * (b2 - minVal) / range;

              S := S + #$1B'[38;2;' + IntToStr(round(r)) + ';' + IntToStr(
                round(g)) + ';' + IntToStr(round(b)) + 'm' +
                #$1B'[48;2;' + IntToStr(round(r2)) + ';' + IntToStr(round(g2)) + ';' + IntToStr(round(b2)) + 'm' + halfChar;
            end;
          end;
        end;
      end;
      write(S, sLineBreak{csi, trunc(scale*_w*tile), 'D' ,dw});
      ow:=math.max(ow, trunc(scale*_w*tile)); inc(oh);
      S := '';
    end;
  end;
  S := #$1B'[0m';
  write(S, sLineBreak);
  result := [ow, oh]

end;

function TTensor<T>.print(const scale: single; const idx: SizeInt): TArray<SizeInt>;
const
      csi =#$1B'[';
      up =#$1B'[A';
      dw =#$1B'[B';
      fw =#$1B'[C';
      bw =#$1B'[D';
      sc =#$1B'[s';
      rc =#$1B'[u';
      er =#$1B'[0K';
      cpos=#$1B'[6n';
var
  amin, amax: T;
  maxVal, minVal: double;
  i, j, k, t, _w, _h, _area, index, outArgMin, outArgMax, ow, oh: SizeInt;
  range, r, r2: double;
  S: string;
const
  __shade: array[0..4] of shortstring = (' ', '░', '▒', '▓', '█');
  halfChar = '▀';
begin
  if not assigned(Data) then exit;
  S := TypeName()+ ' Tensor (';
  for i := 0 to High(Shape) do
    if i = 0 then
      S := S + IntToStr(Shape[i])
    else
      S:= S + ' X '+ intToStr(Shape[i]);
  S := S +')';
  write(S, csi, length(S), 'D', dw);
  ow:=length(S); oh := 1;
  minMax(amin, amax, outArgMin, outArgMax);
  vcvtd(1, @amin, @minVal);
  vcvtd(1, @amax, @maxVal);
  S := '[min : '+ toStr(amin)+ '@'+ IntToStr(outArgMin)+ ', max : '+ toStr(amax)+ '@'+ intToStr(outArgMax)+ ']';
  write(S, csi, length(S), 'D', dw);
  ow:=math.max(ow, length(S)); inc(oh);
  _w := w();
  if length(FShape) > 1 then
  begin
    _h := h;
    _area := _h * _w;
  end
  else
  begin
    _h := 1;
    _area := _w;
  end;
  range := maxVal - minVal;
  if (range < dEPSILON) then exit;
  S := '';
  for j := 0 to trunc(_h * scale / 2) - 1 do
  begin
    for k := 0 to trunc(_w * scale) - 1 do
    begin
      index := idx * _area + round(j * 2 / scale) * _w + round(k / scale);
      if index < size() then
      begin
        vcvtd(1, @Data[index], @r);
        index := idx * _area + round((j * 2 + 1) / scale) * _w + round(k / scale);
        vcvtd(1, @Data[index], @r2);
        r := $ff * (r - minVal) / range;
        r2 := $ff * (r2 - minVal) / range;
        S := S + #$1B'[38;2;' + IntToStr(round(r)) + ';' + IntToStr(round(r)) +
          ';' + IntToStr(round(r)) + 'm' + #$1B'[48;2;' + IntToStr(
          round(r2)) + ';' + IntToStr(round(r2)) + ';' + IntToStr(round(r2)) + 'm' + halfChar;
      end;
    end;
    write(S, csi, trunc(_w * scale), 'D', dw);
    ow:=math.max(ow, trunc(_w * scale)); inc(oh);
    S := '';
  end;
  S := #$1B'[0m';
  write(S);
  result := [ow, oh]

end;

function TTensor<T>.typeName(): string;
begin
  Result := PTypeInfo(TypeInfo(T)).Name;
end;

procedure si2c2(idx:IntPtr; ptr:Pointer);
var
  k, i, j, b, outWidth, outHeight, kernelSize, inSize, outSize,
  kernelCol, kernelRow, outCol, outRow, sizeX,
  kernelWidth, kernelHeight, aChannels, aWidth, dilationX, dilationY,
  strideX, strideY, padWidth, padHeight, batch, chan: SizeInt;
  im, col, im1, col1: PSingle;
  MT :PMPParams absolute ptr;
begin
  outHeight     := PSizeInt(mt.a)^;
  outWidth      := PSizeInt(mt.b)^;
  kernelHeight  := PSizeInt(mt.c)^;
  kernelWidth   := PSizeInt(mt.d)^;
  padHeight     := PSizeInt(mt.e)^;
  padWidth      := PSizeInt(mt.f)^;
  strideY       := PSizeInt(mt.g)^;
  strideX       := PSizeInt(mt.h)^;
  dilationY     := PSizeInt(mt.i)^;
  dilationX     := PSizeInt(mt.j)^;
  batch         := PSizeInt(mt.k)^;
  aChannels     := PSizeInt(mt.l)^;
  inSize        := PSizeInt(mt.m)^;
  outSize       := PSizeInt(mt.n)^;
  sizeX         := PSizeInt(mt.o)^;
  kernelSize    := PSizeInt(mt.p)^;
  aWidth        := PSizeInt(mt.q)^;
  im            := mt.r;
  col           := mt.s;
  //for kernelRow := 0 to kernelHeight - 1 do
  //begin
    chan := idx div kernelSize;
    k    := idx mod kernelSize;
    //for k := 0 to kernelWidth*kernelHeight - 1 do
    begin
      kernelRow := k div kernelWidth;
      kernelCol := k mod kernelWidth;
      for b := 0 to batch - 1 do
      begin
        i := (b * aChannels+ chan) * inSize + aWidth * (kernelRow*dilationY - padHeight) + kernelCol * dilationX - padWidth;
        im1 := im + i;
        col1 := col + padWidth * outWidth + outSize*kernelSize*(chan + b*aChannels) + outSize*(kernelRow * kernelWidth + kernelCol) ;
        for outRow := padHeight to outHeight - padHeight - 1 do
        begin
          j := outRow * aWidth * strideY + padWidth * strideX ;
          if strideX = 1 then
            move(im1[j], col1[padWidth], sizeX * SizeOf(single))
          else
            for outCol := padWidth to outWidth - padWidth - 1 do
            begin
              //j := outRow * aWidth * strideY + outCol * strideX;
              col1[outCol] := im1[j];
              inc(j, strideX);
            end;
          Inc(col1, outWidth);
        end;
      end;
    end;
  //end;
end;

procedure sim2col2(const aChannels, aHeight, aWidth: Sizeint;
  const kernelHeight, kernelWidth, padHeight, padWidth,
  strideY, strideX, dilationY, dilationX: SizeInt;
  const im: PSingle; const imOffset: SizeInt; const col: PSingle;
  const colOffset: SizeInt; const batch: SizeInt = 1; const multithread: boolean = False);
var
  outWidth, outHeight, kernelSize, inSize, outSize, chan, sizeX :SizeInt;
  //i, j, b, kernelCol, kernelRow, outCol, outRow: SizeInt;
  //im1, col1: PSingle;
  mt :TMPParams;
begin
  outWidth := (aWidth + 2 * padWidth - (dilationX * (kernelWidth - 1) + 1)) div strideX + 1;
  outHeight := (aHeight + 2 * padHeight - (dilationY * (kernelHeight - 1) + 1)) div strideY + 1;
  outSize := outWidth * outHeight;
  inSize := aWidth * aHeight;
  kernelSize := kernelWidth * kernelHeight;
  sizeX := outWidth - 2 * padWidth;

  mt.a :=  @outHeight      ;
  mt.b :=  @outWidth       ;
  mt.c :=  @kernelHeight   ;
  mt.d :=  @kernelWidth    ;
  mt.e :=  @padHeight      ;
  mt.f :=  @padWidth       ;
  mt.g :=  @strideY        ;
  mt.h :=  @strideX        ;
  mt.i :=  @dilationY      ;
  mt.j :=  @dilationX      ;
  mt.k :=  @batch          ;
  mt.l :=  @aChannels      ;
  mt.m :=  @inSize         ;
  mt.n :=  @outSize        ;
  mt.o :=  @sizeX          ;
  mt.p :=  @kernelSize     ;
  mt.q :=  @aWidth         ;
  mt.r :=  im + imOffset   ;
  mt.s :=  col + colOffset ;

{$ifdef USE_MULTITHREADING}
  if multithread then
    mp2.&for(si2c2, 0, AChannels*kernelSize, @mt)
  else
{$endif}
  for chan := 0 to aChannels*kernelSize - 1 do
    si2c2(chan, @mt)
end;

procedure sim2Col(const aChannels, aHeight, aWidth: Sizeint;
  const kernelHeight, kernelWidth, padHeight, padWidth,
  strideY, strideX, dilationY, dilationX: SizeInt; const im: PSingle;
  const imOffset: SizeInt; const col: PSingle; const colOffset: SizeInt;
  const batch: SizeInt = 1; const MultiThread: boolean = False);
var
  channel, output_h, output_w, channel_size, out_channel_size, kernel_size: SizeInt;
  {$ifdef FPC}
  procedure i2c_ext(idx:IntPtr; ptr:Pointer);
  {$else}
  i2c_ext: TThreadProcNested;
begin
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opIm2colExt);{$endif}
  i2c_ext := procedure(idx: IntPtr; ptr: Pointer)
  {$endif}
  var
    kernel_row, kernel_col, output_col, output_rows, input_row, input_col: SizeInt;
    d_im, d_col: PSingle;
  begin
    d_im := im + imOffset + channel_size * idx;
    d_col := col + colOffset + kernel_size * out_channel_size * idx;
    for kernel_row := 0 to kernelHeight - 1 do for kernel_col :=
      0 to kernelWidth - 1 do
      begin
        input_row := -padHeight + kernel_row * dilationY;
        for output_rows := 0 to output_h - 1 do
        begin
          if {(input_row>=0) and} (SizeUInt(input_row) < SizeUInt(aHeight)) then
          begin
            input_col := -padWidth + kernel_col * dilationX;
            output_col := 0;
            while output_col < output_w do
            begin
              if {(input_col>=0) and} (SizeUInt(input_col) < SizeUInt(aWidth)) then
                d_col[output_col] := d_im[input_row * aWidth + input_col]
              else
                d_col[output_col] := 0;
              Inc(output_col);
              Inc(input_col, strideX);
            end;
          end
          else
          begin
            for output_col := 0 to output_w - 1 do
            begin
              d_col[output_col] := 0;
            end;
          end;
          Inc(d_col, output_w);
          Inc(input_row, strideY);
        end;
      end;
  end;

  {$ifdef FPC}
begin
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opIm2colExt);{$endif}
  {$else}
  {$endif}
  output_w := (aWidth + 2 * padWidth - (dilationX * (kernelWidth - 1) + 1)) div strideX + 1;
  output_h := (aHeight + 2 * padHeight - (dilationY * (kernelHeight - 1) + 1)) div strideY + 1;
  channel_size := aHeight * aWidth;
  out_channel_size := output_w * output_h;
  kernel_size := kernelWidth * kernelHeight;
  {$ifdef USE_MULTITHREADING}
  if MultiThread then
    mp2.&for(i2c_ext,0, aChannels{, @p})
  else
  for channel:=0 to aChannels-1 do
      i2c_ext(channel,{@p}nil);
  {$else}
  for channel := 0 to aChannels - 1 do
    i2c_ext(channel,{@p}nil);
  {$endif}
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.finish(opIm2colExt);{$endif}
end;

procedure dim2Col(const aChannels, aHeight, aWidth: Sizeint;
  const kernelHeight, kernelWidth, padHeight, padWidth,
  strideY, strideX, dilationY, dilationX: SizeInt; const im: PDouble;
  const imOffset: SizeInt; const col: PDouble; const colOffset: SizeInt;
  const batch: SizeInt = 1; const MultiThread: boolean = False);
var
  channel, output_h, output_w, channel_size, out_channel_size, kernel_size: SizeInt;
  {$ifdef FPC}
  procedure i2c_ext(idx:IntPtr; ptr:Pointer);
  {$else}
  i2c_ext: TThreadProcNested;
begin
  // {$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opIm2colExt);{$endif}
  i2c_ext := procedure(idx: IntPtr; ptr: Pointer)
  {$endif}
  var
    kernel_row, kernel_col, output_col, output_rows, input_row, input_col: SizeInt;
    d_im, d_col: PDouble;
  begin
    d_im := im + imOffset + channel_size * idx;
    d_col := col + colOffset + kernel_size * out_channel_size * idx;
    for kernel_row := 0 to kernelHeight - 1 do for kernel_col :=
      0 to kernelWidth - 1 do
      begin
        input_row := -padHeight + kernel_row * dilationY;
        for output_rows := 0 to output_h - 1 do
        begin
          if {(input_row>=0) and} (SizeUInt(input_row) < SizeUInt(aHeight)) then
          begin
            input_col := -padWidth + kernel_col * dilationX;
            for output_col := 0 to output_w - 1 do
            begin
              if {(input_col>=0) and} (SizeUInt(input_col) < SizeUInt(aWidth)) then
                d_col[output_col] :=
                d_im[input_row * aWidth + input_col]
              else
                d_col[output_col] := 0;
              Inc(input_col, strideX);
            end;
          end
          else
          begin
            for output_col := 0 to output_w - 1 do
            begin
              d_col[output_col] := 0;
            end;
          end;
          Inc(d_col, output_w);
          Inc(input_row, strideY);
        end;
      end;
  end;

  {$ifdef FPC}
begin
    //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opIm2colExt);{$endif}
  {$else}
  {$endif}
  output_w := (aWidth + 2 * padWidth - (dilationX * (kernelWidth - 1) + 1)) div strideX + 1;
  output_h := (aHeight + 2 * padHeight - (dilationY * (kernelHeight - 1) + 1)) div strideY + 1;
  channel_size := aHeight * aWidth;
  out_channel_size := output_w * output_h;
  kernel_size := kernelWidth * kernelHeight;

  {$ifdef USE_MULTITHREADING}
  if MultiThread then
    mp2.&for(i2c_ext,0, aChannels{, @p})
  else
  for channel:=0 to aChannels-1 do
        i2c_ext(channel,{@p}nil);
  {$else}
  for channel := 0 to aChannels - 1 do
    i2c_ext(channel,{@p}nil);
  {$endif}
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.finish(opIm2colExt);{$endif}
end;


procedure c2i(i: IntPtr; ptr: Pointer);
var
  kernel_row, kernel_col, output_rows, output_col, input_row, input_col: SizeInt;
  Height, Width, kernel_h, kernel_w, pad_h, pad_w, stride_h, stride_w
  , dilation_h, dilation_w, colOffset, imOffset, batch,
  output_h, output_w, channel_size, kernel_size, out_channel_size,
  index, chan:SizeInt;
  col, im, data_im, data_col: PSingle;
  p : PMPParams absolute ptr;
begin

  Height            := PSizeInt(p.A)^;
  Width             := PSizeInt(p.B)^;
  kernel_h          := PSizeInt(p.C)^;
  kernel_w          := PSizeInt(p.D)^;
  pad_h             := PSizeInt(p.E)^;
  pad_w             := PSizeInt(p.F)^;
  stride_h          := PSizeInt(p.G)^;
  stride_w          := PSizeInt(p.H)^;
  dilation_h        := PSizeInt(p.I)^;
  dilation_w        := PSizeInt(p.J)^;
  colOffset         := PSizeInt(p.K)^;
  imOffset          := PSizeInt(p.L)^;
  batch             := PSizeInt(p.M)^;
  output_h          := PSizeInt(p.N)^;
  output_w          := PSizeInt(p.O)^;
  out_channel_size  := PSizeInt(p.P)^;
  col               := p.Q ;
  im                := p.R ;

  channel_size      := height*width ;
  kernel_size       := kernel_h * kernel_w;

  chan  := i div (kernel_size);
  data_col := col + colOffset + i*out_channel_size;
  //data_col := col + colOffset + kernel_size*out_channel_size * chan;
  data_im := im + imOffset + channel_size * chan;
  index := (i mod kernel_size);
  kernel_row := index div kernel_w;
  kernel_col := index mod kernel_w;

  //FillDWord(data_im[0], Height * Width, 0);
  //for kernel_row :=0 to kernel_h  - 1 do
  //  for kernel_col :=0 to kernel_w  - 1 do
    begin
      input_row := (kernel_row - pad_h) * dilation_h;
      for output_rows := 0 to output_h - 1 do
      begin
        if not SizeUInt(input_row) < SizeUInt(Height) then
          inc(data_col, output_w)
        else
        begin
          input_col := (kernel_col - pad_w) * dilation_w;
          for output_col := 0 to output_w - 1 do
          begin
            if SizeUInt(input_col) < SizeUInt(Width) then begin
              index := input_row * Width + input_col;
              data_im[index] := data_im[index] + data_col[0];
            end;
            inc(data_col);
            inc(input_col, stride_w);
          end;
        end;
        inc(input_row, stride_h);
      end;
    end;
end;

procedure scol2im(const channels, Height, Width, kernel_h, kernel_w,
  pad_h, pad_w, stride_h, stride_w, dilation_h, dilation_w: SizeInt;
  const col: PSingle; const colOffset: SizeInt;
  const im: PSingle; const imOffset: SizeInt; const batch: SizeInt = 1;
  const multiThread: boolean = False);
var
  channel, output_h, output_w, channel_size, out_channel_size, kernel_size: SizeInt;
  p : TMPParams;
begin
 //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opCol2imExt);{$endif}
  output_h         := (Height + 2 * pad_h - (dilation_h * (kernel_h - 1) + 1)) div stride_h + 1;
  output_w         := (Width + 2 * pad_w - (dilation_w * (kernel_w - 1) + 1)) div stride_w + 1;
  out_channel_size := output_h * output_w;
  channel_size     := Height * Width;
  kernel_size      := kernel_h * kernel_w;

  p.A  := @Height           ;
  p.B  := @Width            ;
  p.C  := @kernel_h         ;
  p.D  := @kernel_w         ;
  p.E  := @pad_h            ;
  p.F  := @pad_w            ;
  p.G  := @stride_h         ;
  p.H  := @stride_w         ;
  p.I  := @dilation_h       ;
  p.J  := @dilation_w       ;
  p.K  := @colOffset        ;
  p.L  := @imOffset         ;
  p.M  := @batch            ;
  p.N  := @output_h         ;
  p.O  := @output_w         ;
  p.P  := @out_channel_size ;
  p.Q  := col               ;
  p.R  := im                ;


  {$ifdef USE_MULTITHREADING}
  if MultiThread then
    mp2.&for(c2i,0, Channels * kernel_size, @p)
  else
  for channel:=0 to Channels*kernel_size-1 do
    c2i(channel, @p);
  {$else}
  for channel := 0 to Channels*kernel_size - 1 do
    c2i(channel,@p);
  {$endif}
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.finish(opCol2imExt);{$endif}
end;

procedure dcol2im(const channels, Height, Width, kernel_h, kernel_w,
  pad_h, pad_w, stride_h, stride_w, dilation_h, dilation_w: SizeInt;
  const col: PDouble; const colOffset: SizeInt;
  const im: PDouble; const imOffset: SizeInt; const batch: SizeInt = 1;
  const multiThread: boolean = False);
var
  channel, output_h, output_w, channel_size, out_channel_size, kernel_size: SizeInt;
  {$ifdef FPC}
  procedure c2i_ext(idx:IntPtr; ptr:Pointer);
  {$else}
  c2i_ext: TThreadProcNested;
begin
  // {$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opCol2ImExt);{$endif}
  c2i_ext := procedure(idx: IntPtr; ptr: Pointer)
  {$endif}
  var
    channel, kernel_row, kernel_col, output_rows, output_col, input_row, input_col: SizeInt;
    data_im, data_col: PDouble;
  begin
    data_col := col + colOffset + kernel_size * out_channel_size * idx;
    data_im := im + imOffset + channel_size * idx;
    FillDWord(data_im[0], Height * Width, 0);
    for kernel_row := -pad_h to kernel_h - pad_h - 1 do
      for kernel_col := -pad_w to kernel_w - pad_w - 1 do
      begin
        input_row := kernel_row * dilation_h;
        for output_rows := 0 to output_h - 1 do
        begin
          if not SizeUInt(input_row) < SizeUInt(Height) then
            Inc(data_col, output_w)
          else
          begin
            input_col := kernel_col * dilation_w;
            for output_col := 0 to output_w - 1 do
            begin
              if SizeUInt(input_col) < SizeUInt(Width) then
                data_im[input_row * Width + input_col] :=
                data_im[input_row * Width + input_col] + data_col[0];
              Inc(data_col);
              input_col := input_col + stride_w;
            end;
          end;
          Inc(input_row, stride_h);
        end;
      end;
  end;

  {$ifdef FPC}
begin
 //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.start(opCol2imExt);{$endif}
  {$else}
  {$endif}
  output_h := (Height + 2 * pad_h - (dilation_h * (kernel_h - 1) + 1)) div stride_h + 1;
  output_w := (Width + 2 * pad_w - (dilation_w * (kernel_w - 1) + 1)) div stride_w + 1;
  out_channel_size := output_h * output_w;
  channel_size := Height * Width;
  kernel_size := kernel_h * kernel_w;
  {$ifdef USE_MULTITHREADING}
  if MultiThread then
    mp2.&for(c2i_ext,0, Channels{, @p})
  else
  for channel:=0 to Channels-1 do
      c2i_ext(channel,{@p}nil);
  {$else}
  for channel := 0 to Channels - 1 do
    c2i_ext(channel,{@p}nil);
  {$endif}
  //{$ifdef USE_TELEMETRY} if benchmark then metrics.ops.finish(opCol2imExt);{$endif}
end;


procedure TTensor<T>.im2Col(const kernelWidth, kernelHeight, padWidth,
  padHeight, strideX, strideY, dilationX, dilationY: SizeInt; var dst: TTensor<T>; const AGroups: SizeInt);
var
  _w, _h, _c, b, ow, oh, colSize, _vol: SizeInt;

  {$ifdef FPC}
procedure i2c(idx:IntPtr; ptr:pointer);
var pmt:PBoolean absolute ptr;
begin
  im2colvv(_c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth, strideY, strideX, dilationY, dilationX, data, idx*_vol, dst.data+ idx*colSize, 0, 1, pmt^)
end;
  {$else}
  da, ds: PT;
  i2c: TThreadProcNested;
  {$endif}
var
  mt: boolean;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opIm2col);
  {$endif}

  assert(assigned(im2colvv), '[Im2Col] not implementd!');
  _c := c();
  _h := h();
  _w := w();
  ow := (_w + 2 * padWidth - (dilationX * (kernelWidth - 1) + 1)) div strideX + 1;
  oh := (_h + 2 * padHeight - (dilationy * (kernelHeight - 1) + 1)) div stridey + 1;
  colSize := _c * oh * ow * kernelWidth * kernelHeight;
  if not assigned(dst.data) then
    dst.resize([groups, _c, kernelHeight*kernelWidth, oh, ow], groups);
  assert(colSize <= dst.Size(),'[im2col], Invalid destination tensor size.');

  _vol := volume();
  {$if not defined(FPC) and not defined(USE_OPENCL)}
  ds := dst.data;
  da := Data;
  i2c := procedure(idx: IntPtr; ptr: pointer)
  var
    pmt: PBoolean absolute ptr;
  begin
    im2colvv(_c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth,
    strideY, strideX, dilationY, dilationX, da, idx * _vol, ds, idx * colSize, 1{groups}, pmt^);
  end;
  {$endif}

{$if defined(_USE_OPENCL)}
  if computingDevice =cdOpenCL then begin
    if not wasGPU() then
      pushToDevice;
    dst.setOCL;
    for b:=0 to Groups-1 do begin
      ocl.FErr := longint(CLBlastSim2col(CLBlastKernelModeCrossCorrelation, _c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth,
        strideY, strideX, dilationY, dilationX, devData , b*_vol, dst.devData, b*colSize, @ocl.ActiveQueue, @ocl.events[0])); ocl.CheckError;
      //ocl.finish
    end;
  end else
{$endif}
  begin
  {$ifdef USE_MULTITHREADING}
    mt := groups=1;
    if groups>1 then
      mp.&for(i2c, 0, groups, @mt)
    else
    for b:=0 to groups-1 do
      i2c(b, @mt);
  {$else}
    mt := False;
    for b := 0 to groups - 1 do
      i2c(b, @mt);
  {$endif}
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opIm2col);
  {$endif}
end;


procedure TTensor<T>.col2Im(const kernelWidth, kernelHeight, padWidth,
  padHeight, strideX, strideY, dilationX, dilationY: SizeInt; var src: TTensor<T>; const AGroups: SizeInt);
var
  _w, _h, _c, b, oh, ow, imSize, colSize: SizeInt;

  {$ifdef FPC}
procedure c2i(idx:IntPtr; ptr:Pointer);
var pmt:PBoolean absolute ptr;
begin
  col2imvv(_c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth, strideY, strideX, dilationY, dilationX, src.data,  idx*colSize, data, idx*imSize, groups, pmt^)
end;
  {$else}
  da, ds: PT;
  c2i: TThreadProcNested;
  {$endif}
var
  mt: boolean;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opCol2im);
  {$endif}
  assert(assigned(col2imvv), '[Col2Im] not implementd!');
  if (not assigned(data)) and (src.dimensions>3) then begin
    ow := src.w;
    oh := src.h;
    _w := (ow - 1) * strideX - 2*padWidth + (dilationX*(kernelWidth-1) + 1);
    _h := (oh - 1) * strideY - 2*padHeight + (dilationX*(kernelHeight-1) + 1);
    _c := src.n();
    resize([src.groups, _c, _h, _w], src.groups);
  end;
  _c := c();
  _h := h();
  _w := w();
  ow := (_w + 2 * padWidth - (dilationX * (kernelWidth - 1) + 1)) div strideX + 1;
  oh := (_h + 2 * padHeight - (dilationy * (kernelHeight - 1) + 1)) div stridey + 1;
  //ow := src.w;
  //oh := src.h;
  //_w := (ow - 1) * strideX - 2*padWidth + (dilationX*(kernelWidth-1) + 1);
  //_h := (oh - 1) * strideY - 2*padHeight + (dilationX*(kernelHeight-1) + 1);
  //_c := src.n();


  colSize := _c * ow * oh * kernelWidth * kernelHeight;
  imSize := _c * _h * _w;
  assert(colSize <= src.Size(), '[col2im] Invalide source tensor size.');
  {$if not defined(FPC) and not defined(_USE_OPENCL)}
  ds := src.data;
  da := Data;
  c2i := procedure(idx: IntPtr; ptr: Pointer)
  var
    pmt: PBoolean absolute ptr;
  begin
    col2imvv(_c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth,
    strideY, strideX, dilationY, dilationX, ds, idx * colSize, da, idx * imSize, 1{groups}, pmt^);
  end;
  {$endif}
  {$if defined(_USE_OPENCL)}
  if computingDevice=cdOpenCL then begin
    if not wasGPU then
      pushToDevice;
    if not src.wasGPU then
      src.pushToDevice;
    for b := 0 to Groups-1 do begin
      ocl.FErr := longint(CLBlastScol2im(CLBlastKernelModeCrossCorrelation, _c, _h, _w, kernelHeight, kernelWidth, padHeight, padWidth
              , strideY, strideX, dilationY, dilationX, src.devData, b*colSize, devData, b*imSize, @ocl.ActiveQueue, @ocl.events[0])); ocl.CheckError;
    end;
    //ocl.finish;
  end else
  {$endif}
  begin
  {$ifdef USE_MULTITHREADING}
    mt := groups=1;
    if groups>1 then
      mp.&for(c2i, 0, groups, @mt)
    else
    for b:=0 to groups-1 do
      c2i(b, @mt);
  {$else}
    mt := False;
    for b := 0 to groups - 1 do
      c2i(b, @mt);
  {$endif}
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opCol2im);
  {$endif}
end;

function TTensor<T>.map(const func: TMapFunc<T>): TTensor<T>;
begin
  Result.resize(FShape);  // note [map] we must initialize the result
  Map(func, self, Result);
end;

function TTensor<T>.map(const func: TMapFuncLambda<T>): TTensor<T>;
begin
  Result.resize(FShape);
  Map(func, self, Result);
end;

procedure TTensor<T>.map(const func: TMapFunc<T>; var dst: TTensor<T>);
begin
  Map(func, self, dst);
end;

procedure TTensor<T>.map(const func: TMapFuncLambda<T>; var dst: TTensor<T>);
begin
  Map(func, self, dst);
end;

procedure TTensor<T>.map(const func: TMapProc<T, PT>);
var
  i: SizeInt;
begin
  for i := 0 to Size() - 1 do
    Data[i] := func(Data[i], i, Self.Shape, Self.Data);
end;

procedure TTensor<T>.map(const func: TMapProcLambda<T, PT>);
var
  i: SizeInt;
begin
  for i := 0 to Size() - 1 do
    Data[i] := func(Data[i], i, Self.Shape, Self.Data);
end;

function TTensor<T>.reduce(const func: TReduceProc<T, PT>): T;
begin
  Result := reduce(func, Data, Size());
end;

function TTensor<T>.reduce(const func: TReduceProc<T, PT>; const start: T): T;
begin
  Result := reduce(func, Data, Size(), 1, start);
end;

function TTensor<T>.reduce(const func: TReduceProcLambda<T, PT>): T;
begin
  Result := reduce(func, Data, Size());
end;

function TTensor<T>.reduce(const func: TReduceProcLambda<T, PT>; const start: T): T;
begin
  Result := reduce(func, Data, Size(), 1, start);
end;

procedure TTensor<T>.concat(const src: array of TTensor<T>);
var
  i, offset: SizeInt;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opConcat);
  {$endif}
  offset := 0;
  for i := 0 to high(src) do
  begin
    src[i].copyTo(self, offset);
    Inc(offset, src[i].Size());
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opConcat);
  {$endif}
end;

procedure TTensor<T>.addConcat(const src: array of TTensor<T>);
var
  i, j, srcSize: SizeInt;
  D: PT;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opAddConcat);
  {$endif}
  D := Data;
  if assigned(addvv) then
  begin
    for i := 0 to high(src) do
    begin
      srcSize := src[i].Size();
      addvv(srcSize, src[i].Data, 1, D, 1, D, 1);
      Inc(D, srcSize);
    end;
    exit;
  end;

  for i := 0 to high(src) do
  begin
    srcSize := src[i].Size();
    for j := 0 to srcSize - 1 do
      D[j] := plus(D[j], src[i].Data[j]);
    Inc(D, srcSize);
  end;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opAddConcat);
  {$endif}
end;

procedure TTensor<T>.getGroup(const idx: SizeInt; const dst: PT);
begin
  move(Data[idx * groupSize()], dst^, groupSize() * SizeOf(T));
end;

class procedure TTensor<T>.histogram(const N: SizeInt; const src: PT;
  const aCount: SizeInt; dst: PInteger; outMin: PT; outMax: PT);
var
  i, j: SizeInt;
  //arr:TArray<SizeInt>;
  minVal, Val: T;
  range, interval: double;
begin
  if not assigned(minmaxvss) then minmaxvss := TTensor<T>.minmax;
  assert(dst <> nil, '[histogram] : [dst] is nil!');
  minMaxvss(N, src, 1, minVal, val);
  if assigned(outMin) then outMin^ := minVal;
  if assigned(outMax) then outMax^ := val;
  if minVal = val then exit;
  val := minus(val, minVal); // rangle
  vcvtd(1, @val, @interval);
  interval := interval / aCount;
  //setLength(arr, aCount);
  for i := 0 to N - 1 do
  begin
    val := minus(src[i], minVal);
    vcvtd(1, @val, @range);
    j := Math.floor(range / interval);
    if j = aCount then
      j := aCount - 1;
    Inc(dst[j]);
  end;
end;


class operator TTensor<T>.Implicit(arr: TArray<T>): TTensor<T>;
begin
  if not assigned(arr) then exit;
  Result.reshape([length(arr)]);
  //result.data := AllocMem(result.ByteSize());
  Result.DynData := Copy(arr);
  Result.Data := Pointer(Result.DynData);
  //move(arr[0], result.data[0], length(arr)*sizeof(T))
end;

class operator TTensor<T>.Implicit(arr: TArray<TArray<T>>): TTensor<T>;
var
  i: SizeInt;
begin
  if not assigned(arr) then exit;
  if not assigned(arr[0]) then exit;
  Result.reshape([length(arr), length(arr[0])]);
  //result.data := AllocMem(result.ByteSize());
  setLength(Result.DynData, Result.Size);
  Result.Data := Pointer(Result.DynData);
  for i := 0 to high(arr) do
    move(arr[i][0], Result.Data[i * length(arr[0])], length(arr[0]) * sizeof(T));
end;

class operator TTensor<T>.Implicit(arr: TArray<TArray<TArray<T>>>): TTensor<T>;
var
  i, j, M, N: SizeInt;
begin
  if not assigned(arr) then exit;
  if not assigned(arr[0]) then exit;
  if not assigned(arr[0][0]) then exit;
  M := length(arr[0]);
  N := length(arr[0][0]);
  Result.reshape([length(arr), M, N]);
  //result.data := AllocMem(result.ByteSize());
  setLength(Result.DynData, Result.Size());
  Result.Data := pointer(Result.DynData);
  for i := 0 to high(arr) do
    for j := 0 to M - 1 do
      move(arr[i][j][0], Result.Data[(i * M + j) * N], N * sizeof(T));
end;

class operator TTensor<T>.Implicit(arr: TArray<TArray<TArray<TArray<T>>>>): TTensor<T>;
var
  i, j, k, M, N, O: SizeInt;
begin
  if not assigned(arr) then exit;
  if not assigned(arr[0]) then exit;
  if not assigned(arr[0][0]) then exit;
  if not assigned(arr[0][0][0]) then exit;
  M := length(arr[0]);
  N := length(arr[0][0]);
  O := length(arr[0][0][0]);
  Result.reshape([length(arr), M, N, O]);
  //result.data := AllocMem(result.ByteSize());
  setLength(Result.DynData, Result.Size());
  Result.Data := pointer(Result.DynData);
  for i := 0 to high(arr) do
    for j := 0 to M - 1 do
      for k := 0 to O - 1 do
        move(arr[i][j][k][0], Result.Data[((i * M + j) * N) * O + k], N * sizeof(T));
end;

class operator TTensor<T>.Implicit(src: TTensor<T>): TArray<T>;
var
  i: SizeInt;
begin
  if src.size() = 0 then exit(nil);
  setLength(Result, src.Size());
  move(src.Data[0], Result[0], src.size() * sizeof(T));
end;

class operator TTensor<T>.Implicit(src: TTensor<T>): PT;
begin
  Result := src.Data;
end;

class operator TTensor<T>.Implicit(src: TTensor<T>): PSingle;
begin
  Result := pointer(src.Data);
end;

class operator TTensor<T>.Implicit(src: TTensor<T>): PDouble;
begin
  Result := pointer(src.Data);
end;

{$ifdef FPC}
class operator TTensor<T>.Initialize(var dst:TTensor<T>);
{$else}

class operator TTensor<T>.Initialize(out dst: TTensor<T>);
  {$endif}
var
  P: PTypeInfo;
  D: PTypeData;
begin
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.start(opInit);
  {$endif}
  dst.steps := 0;
  dst.Data := nil;
  dst.DynData := nil;
  {$if defined(USE_OPENCL)}
  dst.devData := nil;
  dst.lastOp := cdCPU;
  {$endif}
  dst.groups := 0;
  //if assigned(plus) then exit;

  P := TypeInfo(T);
  D := getTypeData(P);
  dst.computingDevice := defaultDevice;;
  case P.kind of
    tkInteger:
      case D.OrdType of
        otUByte:
        begin
          plus := @ubplus;
          minus := @ubminus;
          times := @ubmul;
          division := @ubdiv;
          casti := @ubcasti;
          //vcvtb           := @cvti8b;
          //vcvti8          := @cvti8i8;
          //vcvti16         := @cvti8i16;
          //vcvti32         := @cvti8i32;
          vcvts := @cvtbs;
          vcvtd := @cvtbd;
          toStr := @bToStr;

        end;
        otSByte:
        begin
          plus := @sbplus;
          minus := @sbminus;
          times := @sbmul;
          division := @sbdiv;
          casti := @sbcasti;
          //vcvtb           := @cvti8b;
          //vcvti8          := @cvti8i8;
          //vcvti16         := @cvti8i16;
          //vcvti32         := @cvti8i32;
          vcvts := @cvti8s;
          vcvtd := @cvti8d;
          toStr := @i8ToStr;

        end;
        otSWord:
        begin
          plus := @swplus;
          minus := @swminus;
          times := @swmul;
          division := @swdiv;
          casti := @swcasti;

          //vcvtb           := @cvti16b;
          //vcvti8          := @cvti16i8;
          //vcvti16         := @cvti16i16;
          //vcvti32         := @cvti16i32;
          vcvts := @cvti16s;
          vcvtd := @cvti16d;
          toStr := @i16ToStr;

        end;
        otSLong:
        begin
          plus := @slplus;
          minus := @slminus;
          times := @slmul;
          division := @sldiv;
          casti := @slcasti;
          //vcvtb           := @cvti32b;
          //vcvti8          := @cvti32i8;
          //vcvti16         := @cvti32i16;
          //vcvti32         := @cvti32i32;
          vcvts := @cvti32s;
          vcvtd := @cvti32d;
          toStr := @i32ToStr;
        end;

      end;
    tkInt64:
    begin
      plus := @sqplus;
      minus := @sqminus;
      times := @sqmul;
      division := @sqdiv;
      casti := @sqcasti;
      //vcvtb           := @cvti64b;
      //vcvti8          := @cvti64i8;
      //vcvti16         := @cvti64i16;
      //vcvti32         := @cvti64i32;
      vcvts := @cvti64s;
      vcvtd := @cvti64d;
      toStr := @i64ToStr;
    end;
    tkFloat:
      case D.FloatType of
        ftSingle:
        begin
          plus := @splus;
          minus := @sminus;
          times := @smul;
          division := @sdiv;
          casti := @scasti;
          vcvtb := @cvtsb;
          vcvti8 := @cvtsi8;
          vcvti16 := @cvtsi16;
          vcvti32 := @cvtsi32;
          vcvts := @cvtss;
          vcvtd := @cvtsd;
          toStr := @sToStr;
          checkInf := @IsInfinite;
          checkNan := @isNan;
        end;
        ftDouble:
        begin
          plus := @dplus;
          minus := @dminus;
          times := @dmul;
          division := @ddiv;
          casti := @dcasti;
          vcvtb := @cvtdb;
          vcvti8 := @cvtdi8;
          vcvti16 := @cvtdi16;
          vcvti32 := @cvtdi32;
          vcvts := @cvtds;
          vcvtd := @cvtdd;
          toStr := @dToStr;
          checkInf := @IsInfinite;
          checkNan := @isNan;
        end;

      end;
  end;

  //if not assigned(TTensor<T>.plus) then
  //  TTensor<T>.plus := __plus;

  //if not assigned(TTensor<T>.Minus) then
  //  TTensor<T>.minus := __minus;

  //if not assigned(TTensor<T>.Times) then
  //  TTensor<T>.times := __times;

  //if not assigned(TTensor<T>.Division) then
  //  TTensor<T>.division := __division;

  //if not assigned(TTensor<T>.CastI) then
  //  TTensor<T>.CastI:= __casti;

  if not assigned(TTensor<T>.compare) then
    TTensor<T>.compare := _compare;
  {$ifdef USE_TELEMETRY}
  if benchmark then tensorMetrics.finish(opInit);
  {$endif}
end;

class operator TTensor<T>.Finalize(var dst: TTensor<T>);
begin
  //if assigned(dst.dyndata) then
  //  dst.DynData := nil;
  //if assigned(dst.data) then
  //  dst.Data := nil;

  {$if defined(USE_OPENCL)}
  if assigned(dst.devData) then
  begin
    //ocl.freeDeviceBuffer(dst.devData);
    //dst.devData := nil;
  end;
  {$endif}

  //if assigned(dst.Data) then
  //  FreeMem(dst.Data)
end;

{$ifdef MANAGED_MEM}
{$ifdef FPC}
class operator TTensor<T>.Copy(constref aSrc: TTensor<T>; var aDst: TTensor<T>);
{$else}
class operator TTensor<T>.Assign(var aDst: TManagedRec; const [ref] aSrc: TManagedRec);
{$endif}
var i :SizeInt;
begin
  write('Copy (');
  for i:=0 to High(aSrc.FShape) do
    if i=0 then write(aSrc.FShape[i]) else write(' X ',aSrc.FShape[i]);
  write(') to (');
  for i:=0 to High(aDst.FShape) do
    if i=0 then write(aDst.FShape[i]) else write(' X ',aDst.FShape[i]);
  writeln(')');
  if not assigned(aDst.DynData) and assigned(aDst.Data) then
      FreeMem(aDst.Data);
  aSrc.AssignTo(aDst)
end;
{$endif}

//class operator TTensor<T>.Implicit(arr: TArray<TArray<T>>): TTensor<T>;
//var i:SizeInt;
//begin
//  if not assigned(arr) or not assigned(arr[0]) then exit;
//  result.reshape([length(arr), length(arr[0])]);
//  result.data := AllocMem(length(arr)*length(arr[0])*sizeof(T));
//  for i:=0 to high(arr) do
//     move(arr[i][0], result.data[i*result.w()], result.w()*sizeof(T))
//end;

//class operator TTensor<T>.Implicit(src: TTensor<T>): TArray<TArray<T>>;
//var i: SizeInt;
//begin
//  if src.size()=0 then exit(nil);
//  setLength(result, src.h(), src.w());
//  for i:=0 to high(result) do
//     move(src.data[i*src.w()], result[i][0], src.w()*sizeof(T))
//end;

{$ifdef TENSOR_TEST}
  const N :integer = 99;
  var t1, t2:TTensor<single>;

{$endif}

var
  i: SizeInt;
  cMode: longword;
  hConsole: THandle;
initialization
  SetPrecisionMode(TFPUPrecisionMode.pmSingle);
  {$ifdef USE_MULTITHREADiNG}
  mp.setWorkers(GetSystemThreadCount div TILE_M);
  {$endif}

  TTensor<single>.One := 1.0;
  TTensor<double>.One := 1.0;
  TTensor<int32>.One := 1;
  TTensor<int64>.One := 1;
  TTensor<byte>.One := 1;
  TTensor<shortint>.One := 1;

  TTensor<single>.Zero := 0.0;
  TTensor<double>.Zero := 0.0;
  TTensor<int32>.Zero := 0;
  TTensor<int64>.Zero := 0;
  TTensor<byte>.Zero := 0;
  TTensor<shortint>.Zero := 0;

  //TTensor<Single>.Plus            := _Plus;
  //TTensor<Double>.Plus            := _Plus;
  //TTensor<Int32>.Plus             := _Plus;
  //TTensor<Int64>.Plus             := _Plus;
  //TTensor<byte>.Plus              := _Plus;
  //TTensor<shortint>.Plus          := _Plus;

  //TTensor<Single>.Minus           := _Minus;
  //TTensor<Double>.Minus           := _Minus;
  //TTensor<Int32>.Minus            := _Minus;
  //TTensor<Int64>.Minus            := _Minus;
  //TTensor<byte>.Minus             := _Minus;
  //TTensor<shortint>.Minus         := _Minus;

  //TTensor<Single>.Times           := _Times;
  //TTensor<Double>.Times           := _Times;
  //TTensor<Int32>.Times            := _Times;
  //TTensor<Int64>.Times            := _Times;
  //TTensor<byte>.Times             := _Times;
  //TTensor<shortint>.Times         := _Times;

  //TTensor<Single>.Division        := _Division;
  //TTensor<Double>.Division        := _Division;
  //TTensor<Int32>.Division         := _Division;
  //TTensor<Int64>.Division         := _Division;
  //TTensor<byte>.Division          := _Division;
  //TTensor<shortint>.Division      := _Division;

  //TTensor<Single>.CastI           := Casts;
  //TTensor<Double>.CastI           := Castd;
  //TTensor<Int32>.CastI            := Casti32;
  //TTensor<Int64>.CastI            := Casti64;
  //TTensor<byte>.CastI             := Castu8;
  //TTensor<shortint>.CastI         := Casti8;

  //TTensor<Single>.vcvtb           := @cvtsb;
  //TTensor<Single>.vcvti32         := @cvtsi32;
  //TTensor<Single>.vcvts           := @cvtss;
  //TTensor<Single>.vcvtd           := @cvtsd;

  //TTensor<double>.vcvtb           := @cvtdb;
  //TTensor<double>.vcvti32         := @cvtdi32;
  //TTensor<double>.vcvts           := @cvtds;
  //TTensor<double>.vcvtd           := @cvtdd;

  //TTensor<Byte>.vcvts             := @cvtbs;
  //TTensor<Byte>.vcvtd             := @cvtbd;

  //TTensor<Int32>.vcvts            := @cvtis;
  //TTensor<Int32>.vcvtd            := @cvtid;

  //  TTensor<Single>.toStr           := _ToStr;
  //  TTensor<Double>.toStr           := _ToStr;
  //  TTensor<Int32>.toStr            := _ToStr;
  //  TTensor<Int64>.toStr            := _ToStr;
  //  TTensor<byte>.toStr             := _ToStr;
  //  TTensor<shortint>.toStr         := _ToStr;

  TTensor<single>.Sqr                       := _Sqr;
  TTensor<double>.Sqr                       := _Sqr;
  TTensor<int32>.Sqr                        := _Sqr;
  TTensor<int64>.Sqr                        := _Sqr;
  TTensor<byte>.Sqr                         := _Sqr;
  TTensor<shortint>.Sqr                     := _Sqr;

  TTensor<single>.Sqrt                      := _Sqrt;
  TTensor<double>.Sqrt                      := _Sqrt;
  TTensor<int32>.Sqrt                       := _Sqrt;
  TTensor<int64>.Sqrt                       := _Sqrt;
  TTensor<byte>.Sqrt                        := _Sqrt;
  TTensor<shortint>.Sqrt                    := _Sqrt;

  TTensor<single>.Compare                   := _cmp;
  TTensor<double>.Compare                   := _cmp;
  TTensor<int32>.Compare                    := _cmp;
  TTensor<int64>.Compare                    := _cmp;
  TTensor<byte>.Compare                     := _cmp;
  TTensor<shortint>.Compare                 := _cmp;

  TTensor<single>.rand                      := _rand;
  TTensor<double>.rand                      := _rand;
  TTensor<int32>.rand                       := _rand;
  TTensor<int64>.rand                       := _rand;
  TTensor<byte>.rand                        := _rand;
  TTensor<shortint>.rand                    := _rand;

  TTensor<single>.randG                     := _randG;
  TTensor<double>.randG                     := _randG;
  TTensor<int32>.randG                      := _randG;
  TTensor<int64>.randG                      := _randG;
  TTensor<byte>.randG                       := _randG;
  TTensor<shortint>.randG                   := _randG;

  TTensor<single>.exp                       := _exp;
  TTensor<double>.exp                       := _exp;
  TTensor<int32>.exp                        := _exp;
  TTensor<int64>.exp                        := _exp;
  TTensor<byte>.exp                         := _exp;
  TTensor<shortint>.exp                     := _exp;

  TTensor<single>.log                       := _ln;
  TTensor<double>.log                       := _ln;
  TTensor<int32>.log                        := _ln;
  TTensor<int64>.log                        := _ln;
  TTensor<byte>.log                         := _ln;
  TTensor<shortint>.log                     := _ln;

  TTensor<single>.__abs                     := _abs;
  TTensor<double>.__abs                     := _abs;
  TTensor<int32>.__abs                      := _abs;
  TTensor<int64>.__abs                      := _abs;
  TTensor<byte>.__abs                       := _abs;
  TTensor<shortint>.__abs                   := _abs;

  TTensor<single>.Division                  := _Division;
  TTensor<double>.Division                  := _Division;
  TTensor<int32>.Division                   := _Division;
  TTensor<int64>.Division                   := _Division;
  TTensor<byte>.Division                    := _Division;
  TTensor<shortint>.Division                := _Division;


  TTensor<single>.absv                      := @vAbsI;
  TTensor<double>.absv                      := @vAbsI;
  TTensor<int32>.absv                       := @vAbsI;
  TTensor<int64>.absv                       := @vAbsI;

  TTensor<single>.sqrv                      := @vSqrI;
  TTensor<double>.sqrv                      := @vSqrI;
  TTensor<int32>.sqrv                       := @vSqrI;
  TTensor<int64>.sqrv                       := @vSqrI;
  TTensor<byte>.sqrv                        := @vSqrI;

  TTensor<single>.sqrtv                     := @vSqrtI;
  TTensor<double>.sqrtv                     := @vSqrtI;

  TTensor<single>.absdiffv                  := @vAbsDiffI;
  TTensor<double>.absdiffv                  := @vAbsDiffI;
  TTensor<int32>.absdiffv                   := @vAbsDiffI;
  TTensor<int64>.absdiffv                   := @vAbsDiffI;
  TTensor<byte>.absdiffv                    := @vAbsDiffI;

  TTensor<single>.sumv                      := @vsSumI;
  TTensor<double>.sumv                      := @vdSumI;

  TTensor<single>.rssv                      := @vsRSS;
  TTensor<double>.rssv                      := @vdRSS;

  {$ifdef USE_MKL}
  TTensor<Single>.addvv                     := @mkl_vml.vsAddI;
  TTensor<Double>.addvv                     := @mkl_vml.vdAddI;

  TTensor<Single>.subvv                     := @mkl_vml.vsSubI;
  TTensor<Double>.subvv                     := @mkl_vml.vdSubI;

  TTensor<Single>.mulvv                     := @mkl_vml.vsMulI;
  TTensor<Double>.mulvv                     := @mkl_vml.vdMulI;

  TTensor<Single>.divvv                     := @mkl_vml.vsDivI;
  TTensor<Double>.divvv                     := @mkl_vml.vdDivI;

  {$else}
  TTensor<single>.addvv                     := @vsAddI;
  TTensor<double>.addvv                     := @vdAddI;

  TTensor<single>.subvv                     := @vsSubI;
  TTensor<double>.subvv                     := @vdSubI;

  TTensor<single>.mulvv                     := @vsMulI;
  TTensor<double>.mulvv                     := @vdMulI;

  TTensor<single>.divvv                     := @vsDivI;
  TTensor<double>.divvv                     := @vdDivI;

  {$endif}
  TTensor<single>.addblkvv                  := @vsAddB;
  TTensor<double>.addblkvv                  := @vdAddB;

  TTensor<single>.subblkvv                  := @vsSubB;
  TTensor<double>.subblkvv                  := @vdSubB;

  TTensor<single>.mulblkvv                  := @vsMulB;
  TTensor<double>.mulblkvv                  := @vdMulB;

  TTensor<single>.divblkvv                  := @vsDivB;
  TTensor<double>.divblkvv                  := @vdDivB;

  TTensor<single>.addvs                     := @vssAddI;
  TTensor<double>.addvs                     := @vdsAddI;

  TTensor<single>.subvs                     := @vssSubI;
  TTensor<double>.subvs                     := @vdsSubI;

  TTensor<single>.divvs                     := @vssDivI;
  TTensor<double>.divvs                     := @vdsDivI;

  TTensor<single>.mulAddBlkvv               := @vsMulAddB;
  TTensor<double>.mulAddBlkvv               := @vdMulAddB;

  TTensor<single>.matTra                    := @matsTranspose;
  TTensor<double>.matTra                    := @matdTranspose;

  TTensor<single>.matDeg                    := @matsDegrade;
  TTensor<double>.matDeg                    := @matdDegrade;

  TTensor<single>.matDet                    := @matsDeterminant;
  TTensor<double>.matDet                    := @matdDeterminant;

  TTensor<single>.matCof                    := @matsCofactors;
  TTensor<double>.matCof                    := @matdCofactors;

  TTensor<single>.matInv                    := @matsInverse;
  TTensor<double>.matInv                    := @matdInverse;


  TTensor<int32>.andvv                      := @_and;
  TTensor<int64>.andvv                      := @_and;
  TTensor<byte>.andvv                       := @_and;
  TTensor<shortint>.andvv                   := @_and;

  TTensor<int32>.andvs                      := @_and;
  TTensor<int64>.andvs                      := @_and;
  TTensor<byte>.andvs                       := @_and;
  TTensor<shortint>.andvs                   := @_and;

  TTensor<int32>.orvv                       := @_or;
  TTensor<int64>.orvv                       := @_or;
  TTensor<byte>.orvv                        := @_or;
  TTensor<shortint>.orvv                    := @_or;

  TTensor<int32>.orvs                       := @_or;
  TTensor<int64>.orvs                       := @_or;
  TTensor<byte>.orvs                        := @_or;
  TTensor<shortint>.orvs                    := @_or;

  TTensor<int32>.xorvv                      := @_xor;
  TTensor<int64>.xorvv                      := @_xor;
  TTensor<byte>.xorvv                       := @_xor;
  TTensor<shortint>.xorvv                   := @_xor;

  TTensor<int32>.xorvs                      := @_xor;
  TTensor<int64>.xorvs                      := @_xor;
  TTensor<byte>.xorvs                       := @_xor;
  TTensor<shortint>.xorvs                   := @_xor;

  TTensor<int32>.notv                       := @_not;
  TTensor<int64>.notv                       := @_not;
  TTensor<byte>.notv                        := @_not;
  TTensor<shortint>.notv                    := @_not;

  TTensor<int32>.shrvs                      := @_shr;
  TTensor<int64>.shrvs                      := @_shr;
  TTensor<byte>.shrvs                       := @_shr;
  TTensor<shortint>.shrvs                   := @_shr;

  TTensor<int32>.shlvs                      := @_shl;
  TTensor<int64>.shlvs                      := @_shl;
  TTensor<byte>.shlvs                       := @_shl;
  TTensor<shortint>.shlvs                   := @_shl;

  {$if defined(USE_OPENBLAS)}
  TTensor<single>.gemm                      := @openblas.cblas_sgemm;
  TTensor<double>.gemm                      := @openblas.cblas_dgemm;
  TTensor<single>.axpysvv                   := @openblas.cblas_saxpy;
  TTensor<double>.axpysvv                   := @openblas.cblas_daxpy;
  TTensor<single>.asumv                     := @openblas.cblas_sasum;
  TTensor<double>.asumv                     := @openblas.cblas_dasum;
  TTensor<single>.mulvs                     := @openblas.cblas_sscal;
  TTensor<double>.mulvs                     := @openblas.cblas_dscal;
  TTensor<single>.dotvv                     := @openblas.cblas_sdot;
  TTensor<double>.dotvv                     := @openblas.cblas_ddot;

  //TTensor<Single>.argmaxAbsv      := @openblas.cblas_isamax;
  //TTensor<Double>.argmaxAbsv      := @openblas.cblas_idamax;
  //TTensor<Single>.argminAbsv      := @openblas.cblas_isamin;
  //TTensor<Double>.argminAbsv      := @openblas.cblas_idamin;
  {$elseif defined(USE_MKL)}
  TTensor<Single>.gemm                      := @mkl_cblas.cblas_sgemm;
  TTensor<Double>.gemm                      := @mkl_cblas.cblas_dgemm;
  TTensor<Single>.axpysvv                   := @mkl_cblas.cblas_saxpy;
  TTensor<Double>.axpysvv                   := @mkl_cblas.cblas_daxpy;
  TTensor<Single>.asumv                     := @mkl_cblas.cblas_sasum;
  TTensor<Double>.asumv                     := @mkl_cblas.cblas_dasum;
  TTensor<Single>.mulvs                     := @mkl_cblas.cblas_sscal;
  TTensor<Double>.mulvs                     := @mkl_cblas.cblas_dscal;
  TTensor<Single>.dotvv                     := @mkl_cblas.cblas_sdot;
  TTensor<Double>.dotvv                     := @mkl_cblas.cblas_ddot;
  //TTensor<Single>.gemmBatch       := @mkl_cblas.cblas_sgemm_batch_strided;
  //TTensor<Double>.gemmBatch       := @mkl_cblas.cblas_dgemm_batch_strided;


  //TTensor<Single>.argmaxabsv      := @mkl_cblas.cblas_isamax;
  //TTensor<Double>.argmaxabsv      := @mkl_cblas.cblas_idamax;
  //TTensor<Single>.argminabsv      := @mkl_cblas.cblas_isamin;
  //TTensor<Double>.argminabsv      := @mkl_cblas.cblas_idamin;
  {$else}
  TTensor<Single>.gemm                      := @cblas_sgemm;
  TTensor<Double>.gemm                      := @cblas_dgemm;
  TTensor<Single>.axpysvv                   := @cblas_saxpy;
  TTensor<Double>.axpysvv                   := @cblas_daxpy;
  TTensor<Single>.mulvs                     := @cblas_sscal;
  TTensor<Double>.mulvs                     := @cblas_dscal;
  TTensor<Single>.dotvv                     := @cblas_sdot;
  TTensor<Double>.dotvv                     := @cblas_ddot;


  {$endif}
  //TTensor<single>.im2colvv                  := @sim2Col2;
  TTensor<single>.im2colvv                  := @sim2Col;
  TTensor<double>.im2colvv                  := @dim2Col;
  TTensor<single>.col2imvv                  := @scol2im;
  TTensor<double>.col2imvv                  := @dcol2im;

  TTensor<single>.fmavss                    := @sfmavss;
  TTensor<double>.fmavss                    := @dfmavss;

  TTensor<single>.normvss                   := @snormvss;
  TTensor<double>.normvss                   := @dnormvss;
  {$if defined(CPUX64)}
  if AVX2Support then
    TTensor<Single>.normvss                 := @snormvss_avx;
  {$endif}

  TTensor<single>.normvv                    := @_snormvv;
  TTensor<double>.normvv                    := @_dnormvv;

  TTensor<single>.normblkvv                 := @_snormblkvv;
  TTensor<double>.normblkvv                 := @_dnormblkvv;

  TTensor<single>.MeansAndVarsDelta         := sMeanAndVarianceDelta;
  TTensor<double>.MeansAndVarsDelta         := dMeanAndVarianceDelta;

  TTensor<single>.normalizeDelta            := sNormalizeDelta;
  TTensor<double>.normalizeDelta            := dNormalizeDelta;

  TTensor<single>.sinv                      := @vsin;
  TTensor<single>.cosv                      := @vcos;
  TTensor<single>.tanv                      := @vtan;
  TTensor<single>.cotanv                    := @vcotan;
  TTensor<single>.tanHv                     := @vtanH;
  TTensor<single>.arcsinv                   := @varcsin;
  TTensor<single>.arcCosv                   := @varcCos;
  TTensor<single>.arcTanv                   := @varcTan;
  TTensor<single>.ArcSinHv                  := @vArcSinH;
  TTensor<single>.arcCosHv                  := @varcCosH;
  TTensor<single>.arcTanHv                  := @varcTanH;
  TTensor<single>.log10v                    := @vlog10;
  TTensor<single>.log2v                     := @vlog2;
  TTensor<single>.powv                      := @vPow;
  TTensor<single>.logv                      := @vlog;


  TTensor<double>.sinv                      := @vsin;
  TTensor<double>.cosv                      := @vcos;
  TTensor<double>.tanv                      := @vtan;
  TTensor<double>.cotanv                    := @vcotan;
  TTensor<double>.tanHv                     := @vtanH;
  TTensor<double>.arcsinv                   := @varcsin;
  TTensor<double>.arcCosv                   := @varcCos;
  TTensor<double>.arcTanv                   := @varcTan;
  TTensor<double>.ArcSinHv                  := @vArcSinH;
  TTensor<double>.arcCosHv                  := @varcCosH;
  TTensor<double>.arcTanHv                  := @varcTanH;
  TTensor<double>.log10v                    := @vlog10;
  TTensor<double>.log2v                     := @vlog2;
  TTensor<double>.powv                      := @vPow;
  TTensor<double>.logv                      := @vlog;

  saxpy := @saxpy_pas;
  sdot := @sdot_pas;
  daxpy := @daxpy_pas;
  ddot := @ddot_pas;

  {$if defined(CPUX64) and defined(USE_AVX2)}
  SetupSupport;
  if AVX2Support then
  begin
    saxpy := @saxpy_avx2;
    sdot := @sdot_avx2;
  end;
  {$endif}

  Randomize;
  srnd(randseed);

  _mutex := TCriticalSection.Create;

  {$ifdef MSWINDOWS}
  if IsConsole then
  begin
    hConsole := GetStdHandle(STD_OUTPUT_HANDLE);
    GetConsoleMode(hConsole, @cMode);
    SetConsoleMode(hConsole, (cmode or ENABLE_VIRTUAL_TERMINAL_PROCESSING or
      ENABLE_PROCESSED_OUTPUT){ and not ENABLE_WRAP_AT_EOL_OUTPUT});
  end;
  //write(#$1B'[?1049h'); // set Console Alternative Buffer
  {$endif}



finalization
  FreeAndNil(_mutex);

end.
