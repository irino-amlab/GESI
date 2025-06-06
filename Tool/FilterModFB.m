%
%   Filtering by Modulation Filterbank (MFB)
%   Irino, T.
%   Created:  07 Feb 2022 from modFbank_YK_v2 in mrGEDI by YamaKatsu
%   Modified: 07 Feb 2022
%   Modified: 11 Feb 2022 Separating  calculation of filter coef. and filtering for speed up
%   Modified:  4 Aug 2022  v110  introducing 512 Hz as a default
%   Modified:  3 Jan  2024  corresponding to GESIv130
%   Modified: 18 Nov 2024  introducing MFBparam.MaxFc,  renamed ParamMFB --> MFBpram.  
%   Modified:  7 Dec 2024  introducing MFBparam.MinFc
%
%
%   function [OutMFB, MFBparam] = FilterModFB(Env,MFBparam)
%   INPUT:
%           Env:  The envelope to be filtered
%           MFBparam.fs: sampling frequency of the envelope
%           MFBparam.fc: center frequencies of the modulation filters 
%                                 default: [1 2 4 8 16 32 64 128 256]; --> [1 2 4 8 16 32 64 128 256 512]; 
%           MFBparam.SwPlot:  Plot frequency response of MFB
%
%   OUTPUT:
%           OutMFB:  Temporal outputs for each of the modulation filters
%           MFBparam: Parameter
%
%  See:
%  function x_filt = modFbank_YK_v2(Env,fsEnv,cf_mod) in mrGEDI
%  simply modified some variable names
%
%
%
function [OutMFB, MFBparam] = FilterModFB(Env,MFBparam)
persistent MFcoefIIR

MFBparam.fc_default =[1, 2, 4, 8, 16, 32, 64, 128, 256, 512]; % v110 4 Aug 2022

if isfield(MFBparam,'MaxFc') == 0, MFBparam.MaxFc = MFBparam.fc_default(end); end % 18 Nov 2024
if isfield(MFBparam,'MinFc') == 0,  MFBparam.MinFc = MFBparam.fc_default(1); end % 7 Dec 2024
if MFBparam.MinFc > MFBparam.MaxFc 
    error('MFBparam.MinFc should be less than MFBparam.MaxFc.')
end

NumFc = find(MFBparam.fc_default >= MFBparam.MinFc & MFBparam.fc_default <= MFBparam.MaxFc);
MFBparam.fc = MFBparam.fc_default(NumFc); 

if length(Env) < 1  % when no Env input -- Just return information
    OutMFB = [];  
    return; 
end

% Making filter
if isfield(MFBparam,'fs') ==0,  error('Specify MFBparam.fs'); end
if isfield(MFBparam,'SwPlot') ==0, MFBparam.SwPlot = 0; end

LenFc = length(MFBparam.fc);
if isfield(MFcoefIIR,'a') == 0 | size(MFcoefIIR.a,1) ~= LenFc 
    MFcoefIIR = MkCoefModFilter(MFBparam);  % Making modulation filter
end

[NumEnv, LenEnv] = size(Env);
if NumEnv > 1
    error('Env should be a monoaural row vector.')
end %%%%%%%%

OutMFB = zeros(LenFc,LenEnv);
for nfc = 1:LenFc
    OutMFB(nfc,:) = filter(MFcoefIIR.b(nfc,:), MFcoefIIR.a(nfc,:), Env);
end

MFBparam.MFcoefIIR = MFcoefIIR;

end



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Making coefficients of modulation filterbank
%  The code is the same as in modFbank_YK_v2 in mrGEDI by YamaKatsu
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function MFcoefIIR = MkCoefModFilter(MFBparam)

disp('--- Making modulation filter coefficients ---')
LenFc = length(MFBparam.fc);

IIR_b = zeros(LenFc,4);
IIR_a = zeros(LenFc,4);

for nfc = 1:LenFc

    if MFBparam.fc(nfc) == 1  % when 1 Hz
        % Third order lowpass filter
        [b, a] = butter(3, MFBparam.fc(nfc)/(MFBparam.fs/2));
        b4 = b/a(1);
        a4 = a/a(1);

        IIR_b(nfc,:) = b4;
        IIR_a(nfc,:) = a4;

    else % Bandpass filter
        % Pre-warping
        w0 = 2*pi*MFBparam.fc(nfc)/MFBparam.fs;

        % Bilinear z-transform
        W0 = tan(w0/2);

        % Second order bandpass filter
        Q = 1;
        B0 = W0/Q;
        b = [B0; 0; -B0];
        a = [1 + B0 + W0^2; 2*W0^2 - 2; 1 - B0 + W0^2];
        b3 = b/a(1);
        a3 = a/a(1);

        IIR_b(nfc,1:3) = b3;
        IIR_a(nfc,1:3) = a3;
    end

end

MFcoefIIR.a = IIR_a;
MFcoefIIR.b = IIR_b;

if MFBparam.SwPlot == 1   % plot & pause for confirmation
    PlotFrspMF(MFBparam,MFcoefIIR);
    disp('Return to continue > ');
    pause;
end

end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Plot frequency response of the digital filter
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function PlotFrspMF(MFBparam,MFcoefIIR)

hold on
Nrsl = 1024*4; % > MFBparam.fs;

for nfc = 1:length(MFBparam.fc)
    [frsp, freq] = freqz(MFcoefIIR.b(nfc,:),MFcoefIIR.a(nfc,:),Nrsl,MFBparam.fs);
    plot(freq,20*log10(abs(frsp)));
end

hold off
box on
axis([0.25 max(MFBparam.fc)*2 -40 5]);
grid;
set(gca,'xscale','log');
set(gca,'xtick',MFBparam.fc);
xlabel('Frequency (Hz)');
ylabel('Filter attenuation (dB)');
Str_FcMFB = num2str(MFBparam.fc');
legend(Str_FcMFB,'location','southwest');
title('Modulation filterbank');

end


%%%
%%%

% --- if isfield(MFBparam,'fc') ==0,  MFBparam.fc =[1 2 4 8 16 32 64 128 256]; end
% --- if isfield(MFBparam,'fc') ==0,  MFBparam.fc =MFBparam.fc_default; end % v110 4 Aug 2022
