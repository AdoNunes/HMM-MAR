function [tuda,Gamma,GammaInit,vpath,stats] = tudatrain(X,Y,T,options)
% Performs the Temporal Unconstrained Decoding Approach (TUDA), 
% an alternative approach for decoding where we dispense with the assumption 
% that the same decoding is active at the same time point at all trials. 
% 
% INPUT
% X: Brain data, (time by regions) or (time by trials by regions)
% Y: Stimulus, (time by q); q is no. of stimulus features
%               For binary classification problems, Y is (time by 1) and
%               has values -1 or 1
%               For multiclass classification problems, Y is (time by classes) 
%               with indicators values taking 0 or 1. 
%           If the stimulus is the same for all trials, Y can have as many
%           rows as trials, e.g. (trials by q) 
% T: Length of series or trials
% options: structure with the training options - see documentation in 
%                       https://github.com/OHBA-analysis/HMM-MAR/wiki
% An important option is option.parallel_trials. If set to 1, then 
%   all trials have the same experimental design and that the
%        time points correspond between trials; in this case, all trials
%        must have the same length. If set to 0, then there is not a fixed
%        experimental design for all trials. 
%
% OUTPUT
% tuda: Estimated TUDA model (similar to an HMM structure)
%       It contains the fields of any HMM structure. It also contains:
%           - features: if feature selection is performed, which
%               features have been used
% Gamma: Time courses of the states (decoding models) probabilities given data
% GammaInit: Initialisation state time courses, where we do assume
%       that the same decoding is active at the same time point at all trials.
% vpath: Most likely state path of hard assignments 
% stats: structure with additional information
%   - R2_pca: explained variance of the PCA decomposition used to
%       reduce the dimensionality of the brain data (X)
%   - fe: variational free energy 
%   - R2: (training) explained variance of tuda (time by q) 
%   - R2_states: (training) explained variance of tuda per state (time by q by K) 
%   - R2_stddec: (training) explained variance of the standard 
%               (temporally constrained) decoding approach (time by q by K) 
%
% Author: Diego Vidaurre, OHBA, University of Oxford (2017)

stats = struct();
N = length(T); 
max_num_classes = 5;

classification = length(unique(Y(:))) < max_num_classes;
if classification
    % no demeaning by default if this is a classification problem
    if ~isfield(options,'demeanstim'), options.demeanstim = 0; end
end

% Check options and put data in the right format
options_original = options; 
[X,Y,T,options,A,stats.R2_pca,npca,features] = preproc4hmm(X,Y,T,options); 
parallel_trials = options.parallel_trials; 
options = rmfield(options,'parallel_trials');
if isfield(options,'add_noise'), options = rmfield(options,'add_noise'); end
p = size(X,2); q = size(Y,2);
 
% init HMM, only if trials are temporally related
if ~isfield(options,'Gamma')
    if parallel_trials
        GammaInit = cluster_decoding(X,Y,T,options.K,classification,'regression','',...
            options.Pstructure,options.Pistructure);
        options.Gamma = permute(repmat(GammaInit,[1 1 N]),[1 3 2]);
        options.Gamma = reshape(options.Gamma,[length(T)*size(GammaInit,1) options.K]);
    else
        GammaInit = [];
    end
else
    GammaInit = options.Gamma; 
end

% if cyc==0 there is just init and no HMM training 
if isfield(options,'cyc') && options.cyc == 0 
   if ~parallel_trials
      error('Nothing to do, specify options.cyc > 0') 
   end
   tuda = []; vpath = [];  
   Gamma = options.Gamma;
   stats.R2_stddec = R2_standard_dec(X,Y,T);
   return
end

% Put X and Y together
Ttmp = T;
T = T + 1;
Z = zeros(sum(T),q+p,'single');
for n=1:N
    t1 = (1:T(n)) + sum(T(1:n-1));
    t2 = (1:Ttmp(n)) + sum(Ttmp(1:n-1));
    Z(t1(1:end-1),1:p) = X(t2,:);
    Z(t1(2:end),(p+1):end) = Y(t2,:);
end 

% Run TUDA inference
options.S = -ones(p+q);
options.S(1:p,p+1:end) = 1;
% 1. With the restriction that, for each time point, 
%   all trials have the same state (i.e. no between-trial variability),
%   we estimate a first approximation of the decoding models
options.updateObs = 1; 
options.updateGamma = 0; 
options.updateP = 0;
tuda = hmmmar(Z,T,options);
% 2. Estimate state time courses and transition probability matrix 
options.updateObs = 0;
options.updateGamma = 1;
options.updateP = 1;
options = rmfield(options,'Gamma');
options.hmm = tuda; 
[~,Gamma,~,vpath] = hmmmar(Z,T,options);
% 3. Final update of state distributions, leaving fixed the state time courses
options.updateObs = 1;
options.updateGamma = 0;
options.updateP = 0;
options.Gamma = Gamma;
options = rmfield(options,'hmm');
options.tuda = 1;
% tudamonitoring = options.tudamonitoring;
% if isfield(options,'behaviour')
%     behaviour = options.behaviour;
% else 
%     behaviour = [];
% end
options.tudamonitoring = 0;
options.behaviour = [];
options.verbose = 0;
[tuda,~,~,~,~,~, stats.fe] = hmmmar(Z,T,options); 

tuda.features = features;
if isfield(options_original,'verbose'), tuda.train.verbose = options_original.verbose; end
if isfield(options_original,'embeddedlags'), tuda.train.embeddedlags = options_original.embeddedlags; end 
if isfield(options_original,'standardise'), tuda.train.standardise = options_original.standardise; end  
if isfield(options_original,'onpower'), tuda.train.onpower = options_original.onpower; end 
if isfield(options_original,'detrend'), tuda.train.detrend = options_original.detrend; end 
if isfield(options_original,'filter'), tuda.train.filter = options_original.filter; end 
if isfield(options_original,'downsample'), tuda.train.downsample = options_original.downsample; end 

% Explained variance per state, square error &
% Square error for the standard time point by time point regression
if parallel_trials
    [stats.R2_states,stats.R2] = tuda_R2(X,Y,T-1,tuda,Gamma);
    stats.R2_stddec = R2_standard_dec(X,Y,T-1);
else
    stats.R2_states = []; stats.R2 = []; stats.R2_stddec = [];
end

tuda.train.pca = npca;
tuda.train.A = A; 

end


function [R2_states,R2_tuda] = tuda_R2(X,Y,T,tuda,Gamma)
% training explained variance per time point per each state, for TUDA.
% R2_states is per state, R2_tuda is for the entire model 
N = length(T); ttrial = sum(T)/N; p = size(X,2);
K = length(tuda.state); q = size(Y,2);
R2_states = zeros(ttrial,q,K);
R2_tuda = zeros(ttrial,q);
mY = repmat(mean(Y),size(Y,1),1);
mY = reshape(mY,[ttrial N q]);
Y = reshape(Y,[ttrial N q]);
e0 = permute(sum((mY - Y).^2,2),[1 3 2]);
mat1 = ones(ttrial,q);
mGamma = getFractionalOccupancy (Gamma,T,[],1);
for k = 1:K
    Yhat = X * tuda.state(k).W.Mu_W(1:p,p+1:end);
    Yhat = reshape(Yhat,[ttrial N q]);
    e = permute(sum((Yhat - Y).^2,2),[1 3 2]);
    R2_states(:,:,k) = mat1 - e ./ e0 ;
    R2_tuda = R2_tuda + R2_states(:,:,k) .* repmat(mGamma(:,k),1,q); 
end
end


function R2 = R2_standard_dec(X,Y,T)
% squared error for time point by time point decoding (time by q)
N = length(T); ttrial = sum(T)/N; p = size(X,2); q = size(Y,2);
X = reshape(X,[ttrial N p]);
Y = reshape(Y,[ttrial N q]);
sqerr = zeros(ttrial,1);
sqerr0 = zeros(ttrial,1);
for t = 1:ttrial
    Xt = permute(X(t,:,:),[2 3 1]);
    Yt = permute(Y(t,:,:),[2 3 1]);
    beta = (Xt' * Xt) \ (Xt' * Yt);
    Yhat = Xt * beta; 
    sqerr(t) = sum(sum( (Yhat - Yt).^2 ));
    sqerr0(t) = sum(sum( (Yt).^2 ));
end
R2 = 1 - sqerr ./ sqerr0;
end

