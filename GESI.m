%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
%       Gammachirp Envelope Similarity Index (GESI)
%       Objective mesure index for speech intelligibility including hearing loss
%       Irino, T.
%       Created : 30 Jan 2022   IT, New 1st version
%       Modified: 30 Jan 2022   IT  (v100)
%       Modified:   2 Feb 2022   IT
%       Modified:   7 Feb 2022   IT introducing ModFB
%       Modified:   8 Feb 2022   IT % keeping GCout in GESIparam.DirGCout
%       Modified:   9 Feb 2022   IT % introducing SSIweight(F0mean)
%       Modified: 19 Feb 2022   IT % Tidy up 
%       Modified:   7 Mar 2022   IT using new Eqlz2MeddisHCLevel with GESIparam.DigitalRms1SPLdB, GCFBv232
%       Modified:   9 Mar 2022   IT GECI-> GESI precise naming:  cosine-similarity --  not Correlation
%       Modified:  20 Mar 2022  IT introduction of GCFBv233
%       Modified:  12 May 2022  IT  sum(weightMFB) == 1
%       Modified:  26 May 2022  IT  sum(weightMFB) == 1をやめて戻した。後でmeanで最終の値を求めていることと、STOIと同程度の[a,b]にするため。
%       Modified:   7 Jun  2022   IT  (v108)  Introduced TimeAlignXcorr　+  Taperwindow to SndRef/SndTest
%       Modified:  29 Jul  2022   IT  (v109)  introduced GESIparam.SwWeightProhibit
%       Modified:   4 Aug 2022   IT  v110  introduction of version number +  normalization of SSI weight
%       Modified:  22 Aug 2022   IT  v120  The order of input arguments (SndTest, SndRef, ... ) 
%                                          was replaced to (SndRef, SndTest, ... ) as the same as in stoi,estoi,& haspi
%
%
%
%   Inputs:
%       SndRef:   input signal of speech reference  (always analyzed by NH)
%                           Clean speech or other sounds when comparing NH and HI listeners.
%       SndTest:  input signal of enhanced/unprocessed noisy speech  (NH or HI)
%       GCparam:  parameters of dynamic compressive gammachirp filterbank (dcGC-FB)
%                        GCparam.HLoss: Hearing loss settings
%       GESIparam:   parameter of GESI
%                       GESIparam.fs: Sampling frequency of sounds
%                       GESIparam.DigitalRms1SPLdB: SPL of rms(s(t)) == 1
%                            % Not use -->  GESIparam.SPL: sound pressure level of "SndRef" in dB
%                       GESIparam.NameSndTest: Name of SndTest
%                       GESIparam.NameSndRef: Name of SndRef
%                       GESIparam.MFB: Modulation filterbank parameters
%                       GESIparam.Sim: Similarity parameters
%                       GESIparam.Sigmoid:  (100/(1+exp(ax+b) as in  ESTOI)
%                       GESIparam.IdealObserver =  [k q m sigma_s](not used in the current version)
%
%   Outputs:
%       Result.
%           d:           Metric  = mean(mean(dIntrm))
%           dIntrm:  Intermediate Metric 
%           Pcorrect: percent correct of speech intelligibility calculated  from d
%
%   Note: GCFBv233 is required.
% 
%   Note:  Result.d may fluctuate very slightly in every simulation
%             because of the random noise floor at the output of the GCFB
%
% NOTE: 22 Aug 2022.  Important change  -- Please be careful when using the previous version
%     The order of input arguments was replaced as the same as in stoi,estoi,& haspi
%     v110 and before:  [Result, GESIparam] = GESI(SndTest, SndRef, GCparam, GESIparam)
%     v120 :            [Result, GESIparam] = GESI(SndRef, SndTest, GCparam, GESIparam)
%
%
function [Result, GESIparam] = GESI(SndRef, SndTest, GCparam, GESIparam)

DirProg = fileparts(which(mfilename)); % Directory of this program
addpath([DirProg '/Tool/']);     % Path to Tool
addpath([DirProg '/Tool/world-0.2.4_matlab/']);     % Path to WORLD
Result.Name = 'GESI';
Result.Version = 'v120';  % version number from v120


% making directory and data for keeping GCout
if isfield(GESIparam,'DirGCout') == 0
    GESIparam.DirGCout = [getenv('HOME') '/Data/GESI/GCout/']; %default directory
    if exist(GESIparam.DirGCout) == 0
        mkdir(GESIparam.DirGCout);
    end
end

if isfield(GESIparam,'SwPlot') == 0
    GESIparam.SwPlot = 0;
end

% If the names of Ref & Test sounds, GCoutRef & GCoutTest are saved for speed up.
if isfield(GESIparam,'NameSndRef') == 1
    % GESIparam.NameGCoutRef = ['GCout_' GESIparam.NameSndRef '_Ref' int2str(GESIparam.SPL) 'dB'];
    GESIparam.NameGCoutRef = ['GCout_' GESIparam.NameSndRef '_Rms1SPL' int2str(GESIparam.DigitalRms1SPLdB) 'dB'];
    % example:   **_Ref65dB : reference sound level is 65dB LAeq
    SwSave = 1;
else
    GESIparam.NameGCoutRef = '';
    SwSave = 0;
end
if isfield(GESIparam,'NameSndTest') == 1
    % GESIparam.NameGCoutTest = ['GCout_' GESIparam.NameSndTest '_Ref' int2str(GESIparam.SPL) 'dB'];
    GESIparam.NameGCoutTest = ['GCout_' GESIparam.NameSndTest '_Rms1SPL'  int2str(GESIparam.DigitalRms1SPLdB) 'dB'];
    SwSave = 1;
else
    GESIparam.NameGCoutTest = '';
    SwSave = 0;
end


%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Sound check
%%%%%%%%%%%%%%%%%%%%%%%%%%
[mm1, nn1] = size(SndTest);
[mm2, nn2] = size(SndRef);
if mm1 > 1 && nn1 > 1 || mm2 > 1 && nn2 > 1
    error('SndTest and SndRef should be monaural.')
end
SndRef   = SndRef(:)';  % row vector for GCFB
SndTest = SndTest(:)';

% Time alignment  7 Jun 22
if  length(SndTest) == length(SndRef)
    disp('GESI: No time alignment:  length(SndRef) == length(SndTest)')
    GESIparam.SwTimeAlign = 0; % No alignment
    % SndTest&SndRef are assumed to be prepared properly (e.g. using TaperWindow)

else
    if isfield(GESIparam,'SwTimeAlign') == 0 % controlable from main
        GESIparam.SwTimeAlign = 1;  % default: using Xcorr
    end
    if GESIparam.SwTimeAlign == 1
        disp('GESI: Time alignment of SndTest using TimeAlignXcorr')
        [SndTest, ParamTA] =TimeAlignXcorr(SndTest, SndRef); % Time alignment + length eqaulization
        GESIparam.TimeAlign = ParamTA;
    else
        error('Not prepared yet: Another TimeAlign algorithm.')
    end
    % Taper here for stable estimation
    if isfield(GESIparam,'DurTaperWindow') ==0
        GESIparam.DurTaperWindow = 0.02; % 20ms taper window
    end
    LenTaper = GESIparam.DurTaperWindow *GESIparam.fsSnd;
    Win = TaperWindow(length(SndRef),'han',LenTaper);
    SndRef   = SndRef .* Win;  % row vector
    SndTest  = SndTest .* Win;
end



%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Analysis of GESI
%%%%%%%%%%%%%%%%%%%%%%%%%%
% Default parameters of dcGC filterbank
if isfield(GCparam,'fs')  == 0,         GCparam.fs = 48000; end
if isfield(GCparam,'NumCh')  == 0, GCparam.NumCh = 100; end
if isfield(GCparam,'FRange')  == 0, GCparam.FRange = [100, 8000]; end % covering audiogram
if isfield(GCparam,'OutMidCrct')  == 0,  GCparam.OutMidCrct = 'FreeField'; end % default FreeField  not ELC
if isfield(GCparam, 'HLoss') == 0,   GCparam.HLoss.Type = 'NH';  end  % NH or HL
GCparam.Ctrl = 'dynamic';  % mandatory
GCparam.DynHPAF.StrPrc = 'frame-base'; % mandatory
GCparam.StrFloor = 'NoiseFloor';

%%%%%%%%%%%%%%%%%%%%%%
% Parameters of GESI anaysis 
%%%%%%%%%%%%%%%%%%%%%%
if isfield(GESIparam,'Sim') == 0 || isfield(GESIparam.Sim,'PowerRatio') ==0  % 外部からコントロールできるように
    GESIparam.Sim.PowerRatio = 0.6; % 6:4
    disp('GESIparam.Sim.PowerRatio is set to 0.6 (default) -- OK? Return to continue > ')
    pause
    % Refのpowerで正規化　ーーー　pwrにより大きな違いが出る。按分作戦
    % rPwr = 1; % Refのみ
    % rPwr = 0.75; % 3:1
    % rPwr = 0.6; % 6:4
    %     田丸実験で、 -20dB条件の SRTが人ごとに大きく異なる。これは、あきらかに tone pip数と関連しているであろう。
    %　  個人ごとの違いを出すためにはこれを調整か？
end

[~, MFBparam] = FilterModFB; % always using the default settings of MFB
if isfield(GESIparam.Sim,'weightMFB') ==0  % 外部からコントロールできるように
    LenMFB = length(MFBparam.fc); % length of MFB fc see FilterModFB.m    
    GESIparam.Sim.weightMFB = [ones(LenMFB,1)];
    % GESIparam.Sim.weightMFB = [0; 0; 0; ones(4,1); 0; 0; 0]; % [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]
end


if isfield(GESIparam.Sim,'SwWeightProhibit') == 0  % 外部からコントロールできるように
    GESIparam.Sim.SwWeightProhibit = 1;  % default 禁止領域設定　 introduced 29 Jul 2022
    % 従来法を使いたい場合は、外部で以下のように設定
    % GESIparam.Sim.SwWeightProhibit = 0;
end
if isfield(GESIparam.Sim,'RangeWeightProhibit') == 0  % 外部からコントロールできるように
    GESIparam.Sim.RangeWeightProhibit  = 1; % 禁止領域、とりあえず１倍で計算
end

%%%%%%%%%%%%%%%%%%
% sound  sampling rate conversion & normalization
% GESIparam.fsSnd : sampling frequency of ref/test sounds
%
if GCparam.fs > GESIparam.fsSnd    % Upsampling to 48 kHz
    SndTest = resample(SndTest(:)',GCparam.fs,GESIparam.fsSnd);
    SndRef  = resample(SndRef(:)',GCparam.fs,GESIparam.fsSnd);
end

% Calibrate input level of SndRef by using Meddis hair cell level for GCFB
% [SndRef, MdsAmpdB]   = Eqlz2MeddisHCLevel(SndRef, GESIparam.SPL);
[SndRef, MdsAmpdB]   = Eqlz2MeddisHCLevel(SndRef, [], GESIparam.DigitalRms1SPLdB); % 7 Mar 21
% SndTest should be convert with MdsAmpdB for the same ratio.
SndTest =  10^(MdsAmpdB(2)/20)*SndTest;


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Analysis by dynamic compressive gammachirp filterbank
%GESIparam.NameSndRef GESIparam.NameSndTestがあった場合、GCoutをsaveして、計算時間を短縮
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GCFB analysis of Test signal analyzed by either NH  or HI listener
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
DirNameTest = [GESIparam.DirGCout, GESIparam.NameGCoutTest '.mat'];
if exist(DirNameTest) == 0
    % GCFB analysis
    [GCoutTest, ~, GCparamTest] = GCFBv233(SndTest,GCparam);  % you need GCparam
    GCoutTest = EqlzGCFB2Rms1at0dB(GCoutTest, GCparam.StrFloor);  % 0dB: Abs. Thresh. level


    % ModFB analysis.   MFB is common in Test and Ref
    MFBparam.fs = GCparamTest.DynHPAF.fs;   
    % MFBparam.fcutEnv = 150; %v109以前
    MFBparam.fcutEnv =  max(MFBparam.fc);  % v110  4 Jun 2022  extended fcut of the MFB  for using 512 Hz ModFilter ：　256にする理由もない。
    [MFBparam.bzLPF, MFBparam.apLPF] = butter(1, MFBparam.fcutEnv/(MFBparam.fs/2));

    for nch = 1:GCparam.NumCh
        % frame-base processing, i.e. all positive value
        Env = filter(MFBparam.bzLPF,MFBparam.apLPF,GCoutTest(nch,:)); % LPF
        if  length(find(nch == [1 50 100])) > 0
            disp(['> Modulation Filterbank Analysis: GCFB ch = #' int2str(nch)]);
        end
        [ModEnv, MFBparam] = FilterModFB(Env,MFBparam);
        % Keep the output from modulation filters (NumCh, LenMFB, LenEnv)
        GCModEnvTest(nch,:,:)  = ModEnv;
    end

    if SwSave == 1
        disp(['save: ' DirNameTest ])
        save(DirNameTest,'GCoutTest','GCparamTest','GCModEnvTest','MFBparam');
    end
else
    disp(['load: ' DirNameTest ])
    load(DirNameTest);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% GCFB analysis of Ref analyzed by a NH listener
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
DirNameRef = [GESIparam.DirGCout, GESIparam.NameGCoutRef '.mat'];
if exist(DirNameRef) == 0
    % GCFB analysis
    GCparam.HLoss.Type = 'NH';  % overwrite
    [GCoutRef, ~, GCparamRef] = GCFBv233(SndRef,GCparam);
    GCoutRef = EqlzGCFB2Rms1at0dB(GCoutRef, GCparam.StrFloor);
    % GCoutRef = EqlzGCFB2Rms1at0dB(GCoutRef, GCparam.StrFloor)+ alpha*randn(GCparamRef.NumCh,length(GCoutRef)); % Add noise, 28 Apr, Yamamoto

    for nch = 1:GCparam.NumCh
        % frame-base processing, i.e. all positive value
        Env = filter(MFBparam.bzLPF,MFBparam.apLPF,GCoutRef(nch,:)); % LPF
        if  length(find(nch == [1 50 100])) > 0
            disp(['> Modulation Filterbank Analysis: GCFB ch = #' int2str(nch)]);
        end
        [ModEnv, ~] = FilterModFB(Env,MFBparam);
        % Keep the output from modulation filters (NumCh, LenMFB, LenEnv)
        GCModEnvRef(nch,:,:)  = ModEnv;
    end

    % Mean Fo analysis of Ref & SSIweight using world
    HarvestRef = Harvest(SndRef,GCparam.fs); % every 5ms
    F0MeanRef =  geomean(HarvestRef.f0(HarvestRef.f0>0)); %geomean of F0
    disp(['Fo Mean of Ref sound: ' num2str(F0MeanRef,'%5.1f') ' Hz']);
    SSIparam.Fr1        = GCparamRef.Fr1;
    SSIparam.F0_limit = F0MeanRef;
    [SSIweight, SSIparam] = F0limit2SSIweight(SSIparam);
    %    SSIparam.weight = SSIweight; % for keeping weight  v109 and before
    
    %%%  Introdued normalization of SSIweight  v110    4 Aug 2022
    SSIparam.F0_limit_Norm = 125; % F0 for normalization
    SSIparamNorm = SSIparam; % copy    
    SSIparamNorm.F0_limit = SSIparam.F0_limit_Norm ; % freq for normalization
    [SSIweightNorm] = F0limit2SSIweight(SSIparamNorm);
    SSIparam.weight_AmpNorm = sum(SSIweightNorm)/sum(SSIweight);
    SSIparam.weight = SSIparam.weight_AmpNorm * SSIweight;  % normalization
    %%%%%%

    if SwSave == 1
        disp(['save: ' DirNameRef ])
        save(DirNameRef,'GCoutRef','GCparamRef','GCModEnvRef','SSIparam');
    end
else
    disp(['load: ' DirNameRef ])
    load(DirNameRef);
end

GESIparam.GCparam.Ref = GCparamRef;
GESIparam.GCparam.Test = GCparamTest;
GESIparam.MFBparam  = MFBparam;  % common in Test and Ref
GESIparam.SSIparam = SSIparam;   % only in Ref

if GESIparam.SwPlot == 1
    gcfKeep = gcf;
    figure(gcfKeep.Number+1); clf

    amp = 6;  % max(GCFB output) は30程度なのでこれに設定
    subplot(2,1,1);  image(amp*GCoutTest); set(gca,'YDir','normal');
    subplot(2,1,2);  image(amp*GCoutRef);  set(gca,'YDir','normal');
    drawnow
    figure(gcfKeep.Number+2); clf
    plot(SSIparam.weight)
    figure(gcfKeep.Number); % 元のfigure numberにもどす
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Cosine similarity analysis
%   素直にここで時間軸方向のcosine類似度も取ったらちょうどよかった　corrではない。
%   chごとに計算するので、ここでSSI weightを入れられる。-- Linearな計算なので順番入れ替えもOK
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
[NumCh, LenMFB, LenEnv]  = size(GCModEnvRef);
%%% ---> not used:  weightMFB   = GESIparam.Sim.weightMFB/sum(GESIparam.Sim.weightMFB); % sum = 1;  % 12 May 22

weightMFB  = GESIparam.Sim.weightMFB; % 26 May 22 こちらに戻した。後でmeanで最終の値を求めていることと、STOIと同程度の[a,b]にするため。
weightGCFB = SSIparam.weight;

% Calculation of cosine similarity
for nch = 1:NumCh  % == GCparam.NumCh
    for nMFB = 1:LenMFB
        ModEnvRef  = GCModEnvRef(nch,nMFB,:);
        ModEnvTest = GCModEnvTest(nch,nMFB,:);

        PwrRef   = sum(ModEnvRef.^2);      % sum power
        PwrTest = sum(ModEnvTest.^2);      % sum power
        rPwr = GESIparam.Sim.PowerRatio;   % power ratio  0<=rPwr<=1
        
        CosSim = sum(ModEnvRef.*ModEnvTest)/(PwrRef^rPwr*PwrTest^(1-rPwr));
        CosSimMtrx(nch,nMFB) = CosSim;   
                % CosSimMtrx(nch,nMFB)　= min(CosSim,1); % ほぼ同じなので、１で制限は意味ないと思う。　

        % Setting weight 
        weightMtrx(nch,nMFB) = weightGCFB(nch)*weightMFB(nMFB);
        if GESIparam.Sim.SwWeightProhibit == 1 % 禁止領域を設けたweight
            if GCparamRef.Fr1(nch) < MFBparam.fc(nMFB)*GESIparam.Sim.RangeWeightProhibit 
                % Ch Freq < Modulation Freq は計算上意味がないので、無効に
                weightMtrx(nch,nMFB) = NaN; % 無効な場合
            end
        end
    end
end

% 指標の名前　dGCMFBtmc: d (GC+MFB) + temporal coefficient
dGCMFBtmc = weightMtrx.*CosSimMtrx; % nCh * nMFB それぞれの値を保持　
Result.dIntrm.GCMFBtmc   = dGCMFBtmc;  % Original intermediate  中間表現としての d
Result.d.GCMFBtmc           = mean(dGCMFBtmc(~isnan(dGCMFBtmc))); % NaNでないところの平均　29 Jul 22
Result.Pcorrect.GCMFBtmc = Metric2Pcorrect_Sigmoid(Result.d.GCMFBtmc,GESIparam.Sigmoid); %　Pcorrect仮出力

% plot Result.dIntrm.GCMFBtmc 
if GESIparam.SwPlot == 2
    image(Result.dIntrm.GCMFBtmc*256)
    set(gca,'YDir','normal');
    xlabel('MFB channel')
    ylabel('GCFB channel')
    drawnow
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 将来の変更に対する余地を残している。
% 最終結果は、以下のよう出力を決めうちして、GESIという名前にしたい。
%%%%%%%%%%%%%%%%%%%%%%%%%%%%
Result.Note       = 'Result.d.GESI  == Result.d.GCMFBtmc';
Result.d.GESI    = Result.d.GCMFBtmc;
Result.Pcorrect.GESI = Result.Pcorrect.GCMFBtmc;


end % function




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Trash & Memo
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%

% Previous implementation
% dGCMFBtmc(nch,nMFB) = weightGCFB(nch)*weightMFB(nMFB)*CosSim; %



%% History of variants.
%  Basically they were not very successful. -- Comment out now
%%%%%%%%%%%%%%%%%%%%%%
% Correlation analysis of ESTOI like in spectral domain: frame by frame
% GESI_CorrFrame
% correlation anaysis in MFB spectral dimension
% GESI_CorrMFBspec
%  Memo and trash
% GESI_Memo


% if isfield(GESIparam.Sim, 'ThrshLowPower') == 0
%     GESIparam.Sim.ThrshLowPower = 1.5;
% end

    % Absolute thresholdより内部の雑音の方が影響 YA
    % GCoutTest = EqlzGCFB2Rms1at0dB(GCoutTest, GCparam.StrFloor) + alpha*randn(GCparamTest.NumCh,length(GCoutTest)); % Add noise, 28 Apr, Yamamoto.

% ModEnvRef  = GCModEnvRef(nch,nMFB,:);
% ModEnvTest = GCModEnvTest(nch,nMFB,:);
%  これにrPwrを入れた場合、80/70yr 反転問題は解消したものの、Unprocが一番下、LowLevelが一番上。これはダメ。
%  -->   重み関数の導入　SSIweight
%  9 Feb 22
%     SSI weightこそ、ここで使える。
%     Articulation indexの重み付け係数^0.3とほぼ同等となるので、説明できる....
%     0.3乗は、compression分。でもAIは、dB上の重み関数。
%     See  ./Tool/testArticulationIndexHL.m
%  19 Feb 22
%   ... と思ったのはこじつけかも。
%  20 Feb 22
%   計算の手順上、ModEnvRef/ModEnvTestのところに入れる。

%
        % crTmp= corrcoef(ModEnvRef,ModEnvTest);  Pearson Correlation:  =="rPwr =0.5"
        % dGCMFBtmpPC(nch,nMFB) = crTmp(1,2);

% rPwr = 0.6 SSIweight:   Unpro == LowL > 70yr > 80yr  ほぼOK
% rPwr = 0.6 : pwr== 1.2, Wt8, Wt9  Unpro == LowL > 70yr > 80yr  ほぼOK
%  rPwr = 0.75 : pwr== 1.5, Wt8 Unpro >> LowL > 70yr > 80yr  LowL小さい。80yrもっとあげたい
%  rPwr = 0.75 : pwr== 1.5, Wt6 Unpro >> 70yr ==  > 80yr   LowLは下がる。高い周波数重要
% pwr== 0.75, Wt7 Unpro = LowL >> 70yr > 80yr レベルがだいぶあってきた
% pwr== 1: pwr== 2, Wt7 Unpro >> LowL >> 70yr > 80yr 傾向的にはOKだが、やはり、レベルが違いすぎ
% pwr== 1: pwr== 2, Wt5 Wt6 も同じ傾向　Unpro >>> 70yr > > 80yr
% Result.dIntrm.GCMFBtmp   = dGCMFBtmp;  % Pearson Correlation Original intermediate d
% Result.d.GCMFBtmp           = mean(mean(Result.dIntrm.GCMFBtmp));
% Result.Pcorrect.GCMFBtmp = Metric2Pcorrect_Sigmoid(Result.d.GCMFBtmp,GESIparam.Sigmoid);
% if GESIparam.SwPlot == 1
%     subplot(2,1,1);  imagesc(dGCMFBtmp);
%     subplot(2,1,2);  imagesc(dGCMFBtmprPwr);
% end
% 

%       以下の組み合わせはダメ
%       ModEnvRef  = SSIparam.weight(nch)*GCModEnvRef(nch,nMFB,:);
%         ModEnvTest = GCModEnvTest(nch,nMFB,:);

% こちらは、normalizeした方がband数によっての変動を吸収できる。
% weightMFB   = GESIparam.Sim.weightMFB/sum(GESIparam.Sim.weightMFB); % sum = 1;  % 12 May 22
%
% weightGCFBは、Foによって変わってしまうため、以下は使わない方が良い。
% weightGCFB = SSIparam.weight/sum(SSIparam.weight); % sum == 1    % 12 May 22



        % ModEnvRef  = squeeze(GCModEnvRef(nch,nMFB,:)) + 0.5*randn(LenEnv,1); % リファレンスにもnoiseをつけてみる, 2 May, YA
        % ModEnvTest = squeeze(GCModEnvTest(nch,nMFB,:)) + 0.5*randn(LenEnv,1); % Add noise, 27 Apr, YA
