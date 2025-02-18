function Gamma = cluster_decoding(X,Y,T,K,classification,cluster_method,...
    cluster_measure,Pstructure,Pistructure,GammaInit,repetitions)
% clustering of the time-point-by-time-point regressions, which is
% temporally constrained unlike TUDA
% INPUT
% X,Y,T are as usual
% K is the number of states
% cluster_method is 'regression', 'hierarchical', or 'sequential'
% cluster_measure is 'error', 'response' or 'beta', only used if 
%       cluster_method is 'hierarchical'
% Pstructure and Pistructure are constraints in the transitions
% GammaInit: Initial state time course (optional)
% repetitions: How many times to repeat the init (only used if
%       cluster_method is 'sequential'
% OUTPUT
% Gamma: (trial time by K), containing the cluster assignments

if nargin<6, cluster_method = 'regression'; end
if nargin>6 && ~isempty(cluster_measure) && strcmp(cluster_method,'regression')
    warning('cluster_measure is not used when cluster_method is regression')
end
if nargin<7, cluster_measure = 'error'; end
if nargin<8, Pstructure = true(K,1); end
if nargin<9, Pistructure = true(K); end
if nargin<10, GammaInit = []; end
if nargin<11, repetitions = 100; end


N = length(T); p = size(X,2); q = size(Y,2); ttrial = T(1);
X = reshape(X,[ttrial N p]);
Y = reshape(Y,[ttrial N q]);
if strcmp(cluster_method,'regression')
    max_cyc = 100;
    % start with no constraints
    if isempty(GammaInit)
        Gamma = cluster_decoding(reshape(X,[ttrial*N p]),reshape(Y,[ttrial*N q]),...
            T,K,classification,'sequential',[],[],[],[],1000);
    else
        Gamma = GammaInit; 
    end
    assig = zeros(ttrial,1);
    for t=1:ttrial, assig(t) = find(Gamma(t,:)==1); end
    j1 = assig(1);
    if ~Pistructure(j1) % is it consistent with constraint?
        j = find(Pistructure,1);
        Gamma_j = Gamma(:,j);
        Gamma(:,j) = Gamma(:,j1);
        Gamma(:,j1) = Gamma_j;
        for t=1:ttrial, assig(t) = find(Gamma(t,:)==1); end
    end
    assig_pr = assig;
    beta = zeros(p,q,K);
    err = zeros(ttrial,K);
    for cyc = 1:max_cyc
        % M
        for k = 1:K
            ind = assig==k;
            Xstar = reshape(X(ind,:,:),[sum(ind)*N p]);
            Ystar = reshape(Y(ind,:,:),[sum(ind)*N q]);
            beta(:,:,k) = (Xstar' * Xstar) \ (Xstar' * Ystar);
        end
        % E
        Y = reshape(Y,[ttrial*N q]);
        for k = 1:K
            Yhat = reshape(X,[ttrial*N p]) * beta(:,:,k);
            e = sum((Y - Yhat).^2,2);
            e = reshape(e,[ttrial N]);
            err(:,k) = sum(e,2);
        end
        Y = reshape(Y,[ttrial N q]);
        err(1,~Pistructure) = Inf;
        [~,assig(1)] = min(err(1,:));
        for t = 2:ttrial
            err(t,~Pstructure(assig(t-1),:)) = Inf;
            [~,assig(t)] = min(err(t,:));
        end
        % terminate?
        %if ~all(Pstructure(:)), keyboard; end
        if all(assig_pr==assig), break; end
        assig_pr = assig;
    end
    for t = 1:ttrial
        Gamma(t,:) = 0;
        Gamma(t,assig(t)) = 1;
    end
elseif strcmp(cluster_method,'hierarchical')
    beta = zeros(p,q,ttrial);
    for t = 1:ttrial
        Xt = permute(X(t,:,:),[2 3 1]);
        Yt = permute(Y(t,:,:),[2 3 1]);
        beta(:,:,t) = (Xt' * Xt) \ (Xt' * Yt);
    end
    if strcmp(cluster_measure,'response')
        dist = zeros(ttrial*(ttrial-1)/2,1);
        dist2 = zeros(ttrial,ttrial);
        Xstar = reshape(X,[ttrial*N p]);
        c = 1;
        for t2 = 1:ttrial-1
            d2 = Xstar * beta(:,:,t2);
            for t1 = t2+1:ttrial
                d1 = Xstar * beta(:,:,t1);
                dist(c) = sqrt(sum(sum((d1 - d2).^2)));
                dist2(t1,t2) = dist(c);
                dist2(t2,t1) = dist(c);
                c = c + 1;
            end
        end
    elseif strcmp(cluster_measure,'error')
        dist = zeros(ttrial*(ttrial-1)/2,1);
        dist2 = zeros(ttrial,ttrial);
        c = 1;
        for t2 = 1:ttrial-1
            Xt2 = permute(X(t2,:,:),[2 3 1]);
            Yt2 = permute(Y(t2,:,:),[2 3 1]);
            for t1 = t2+1:ttrial
                Xt1 = permute(X(t1,:,:),[2 3 1]);
                Yt1 = permute(Y(t1,:,:),[2 3 1]);
                error1 = sqrt(sum(sum((Xt1 * beta(:,:,t2) - Yt1).^2)));
                error2 = sqrt(sum(sum((Xt2 * beta(:,:,t1) - Yt2).^2)));
                dist(c) = error1 + error2; c = c + 1;
                dist2(t1,t2) = error1 + error2;
                dist2(t2,t1) = error1 + error2;
            end
        end
    elseif strcmp(cluster_measure,'beta')
        beta = permute(beta,[3 1 2]);
        beta = reshape(beta,[ttrial p*q]);
        dist = pdist(beta);
    end
    if iseuclidean(dist')
        link = linkage(dist','ward');
    else
        link = linkage(dist');
    end
    assig = cluster(link,'MaxClust',K);
else % 'sequential'
    assig = zeros(ttrial,1);
    err = 0;
    changes = [1 (1:(K-1)) * round(ttrial / K) ttrial];
    Ystar = reshape(Y,[ttrial*N q]);
    for k = 1:K
        assig(changes(k):changes(k+1)) = k;
        ind = assig==k;
        Xstar = reshape(X(ind,:,:),[sum(ind)*N p]);
        Ystar = reshape(Y(ind,:,:),[sum(ind)*N q]);
        beta = (Xstar' * Xstar + 0.0001*eye(size(Xstar,2))) \ (Xstar' * Ystar);
        err = err + sqrt(sum(sum((Ystar - Xstar * beta).^2,2)));
    end
    err_best = err; assig_best = assig;
    for rep = 1:repetitions
        assig = zeros(ttrial,1);
        while 1
            changes = cumsum(rand(1,K));
            changes = [1 round(ttrial * changes / max(changes))];
            if ~any(changes==0) && length(unique(changes))==length(changes) 
                break 
            end
        end
        err = 0;
        for k = 1:K
            assig(changes(k):changes(k+1)) = k;
            ind = assig==k;
            Xstar = reshape(X(ind,:,:),[sum(ind)*N p]);
            Ystar = reshape(Y(ind,:,:),[sum(ind)*N q]);
            beta = (Xstar' * Xstar + 0.0001*eye(size(Xstar,2))) \ (Xstar' * Ystar);
            err = err + sqrt(sum(sum((Ystar - Xstar * beta).^2,2)));
        end
        if err < err_best
            err_best = err; assig_best = assig;
        end
    end
    assig = assig_best;
        
end

Gamma = zeros(ttrial, K);
for k = 1:K
    Gamma(assig==k,k) = 1;
end
end

