function [a score] = profileHMM_annotate_lambda(seq, V_seq, D_seq, J_seq, params)
% Given specific values for V, D, and J, find the best annotation.
% Using dynamic programming (Viterbi)

a = struct('V', [], 'N1', [], 'D', [], 'N2', [], 'J', [], 'V_', [], 'D_', [], 'J_', [], 'eaten', [0 0 0 0]);

if nargin == 0, unittest(); return; end
if nargin < 5, params = profileHMM_get_params(); end
assert(isempty(D_seq))

    sigma = params.noise;  % emission noise
    
    X = seq;
    map('ACGTNacgtn-') = [1:5, 1:5, 5];
    if X(1)>5
        X = map(X);
    end

    eaten = [0 0 0 0];
    if length(V_seq) > length(seq) 
        eaten(1) =  length(V_seq) - length(seq);
        V_seq = V_seq(1:length(seq));
    end
    
    if length(J_seq) > length(seq) 
        eaten(4) = length(J_seq) - length(seq);
        J_seq = J_seq(end-length(seq)+1:end);
    end


    if V_seq(1)>5
        V_seq = map(V_seq);        
        J_seq = map(J_seq);
    end

    lV = length(V_seq);    
    lJ = length(J_seq);
    L = length(X);
    lP = length(params.P_del(1).pdf); % max number of deletions in each region
    lN = length(params.N_add(1).pdf)-1; % max number of N-additions in each region
    emit = log((1-4*sigma)*eye(5)+sigma);
    emit(5, 1:4) = log(0.25); 
    emit(:, 5) = 0;
    N_emit = repmat([log([0.15 0.35 0.35 0.15]) 0], lN, 1);


    %  ASSUMPTION - read has no insertions or deletion!  
    %  Obviously this assumption is not true.

%%  Compute V
    v_match = cumsum(emit(sub2ind(size(emit), V_seq', X(1:lV)' )));

    len_ = min(lV, lP);
    v_pdel = -inf*ones(lV,1);
    v_pdel(end-len_+1:end) = log(flipud(params.P_del(1).pdf(1:len_)));

    %v(i) = prob that the letters X(1:i) map to the entire V-region
    v = v_match+v_pdel;

%% compute N1
    n1_match = -inf*ones(lN+1, L+1);
    n1_match(1,1+(1:lV)) = v;
    for k=1:lN        
        n1_match(k+1, 2:end) = n1_match(k, 1:end-1) + N_emit(k,X);
    end
        
    n1_add = repmat(log(params.N_add(1).pdf), 1, L+1);
    [n1 n1_parent] = max(n1_match + n1_add); % n1_parent = no. additions + 1


%%  Compute J
    j_match = flipud(cumsum(flipud(emit(sub2ind(size(emit), J_seq', X(end-lJ+1:end)' )))));
    
    len_ = min(lJ, lP);
    j_pdel = -inf*ones(lJ,1);
    j_pdel(1:len_) = log(params.P_del(4).pdf(1:len_));

    %j(i) = prob that the letters X(end-lJ+i:end) map to the entire J-region
    %        (in other words, eating i-1 letters from J)
    j = j_match+j_pdel;

%%  compute final score

    % n1(L)      <--> j(lJ)
    % n1(L+1-lJ) <--> j(1)
    % n1(i)      <--> j(i+Lj-L)
    j_embeded = -inf*ones(1, L+1);
    j_embeded(end-lJ:end-1) = j;
    [score S_parent] = max(j_embeded + n1);

    % if score is -Inf the sequence is too long
    if isinf(score)
        a.V_ = V_seq;
        a.J_ = J_seq;
        a.N1 = X(lV+1 : end-lJ);
        a.germline = [a.V_ 5*ones(size(a.N1)) a.J_];
        return;          
    end

    j_start = S_parent;  % correct
    
    %%%%%% improvising
    
    v_end = j_start-n1_parent(j_start);

    % return vector how much was erased from every gene:
    % a.eaten = [lV-v_end k-2 lD-k+2-(d_end-d_start+1) j_start+lJ-1-L];
    a.eaten = [lV-v_end 0 0 j_start+lJ-1-L];

    a.V_ = V_seq(1 : (end-a.eaten(1)) ); 
    a.D_ = []
    a.J_ = J_seq((a.eaten(4)+1) : end);
%     prototype = [V_seq 5*ones(size(N1)) D_seq 5*ones(size(N2)) J_seq];        
%     ix = [1 v_end; v_end+1:d_start-1; d_start:d_end; d_end+1:j_start-1; j_start:end];
    
    a.V = X(1:v_end);
    a.N1 = X(v_end+1:j_start-1);
    a.D = [];
    a.N2 = [];
    a.J = X(j_start:end);
    a.germline = [a.V_ 5*ones(size(a.N1)) a.J_];

    a.eaten = a.eaten+eaten;
    
end

function unittest()
    
    dict = 'ACGTN';

    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    
    % case 1 - perfect
    [V_ N1_ D_ N2_ J_] = deal(V0, '', D0, '', J0);
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));

    % case 2 - V deletions
    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    [V_ N1_ D_ N2_ J_] = deal('AAA', '', D0, '', J0);
%    [V N1 D N2 J] = profileHMM_annotate([V_ N1_ D_ N2_ J_], V0, D0, J0);
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));
    
    % case 3 - J deletions
    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    [V_ N1_ D_ N2_ J_] = deal(V0, '', D0, '', 'TTT');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));

    % case 3b - J is more likely to lose the nucleotides than V
    [V0 D0 J0] = deal('AAATT', '', 'TTAAA');
    [V_ N1_ D_ N2_ J_] = deal('AAATT', '', '', '', 'AAA');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));    
   
    % case 4 - more deletions deletions
    [V0 D0 J0] = deal('AAATT', '', 'CCAAA');
    [V_ N1_ D_ N2_ J_] = deal('AAAT', '', D0, '', 'CAAA');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));
    
    % case 5 - deletions everywhere
    [V0 D0 J0] = deal('AAATTT', '', 'CCCCTTT');
    [V_ N1_ D_ N2_ J_] = deal('AAA', '', D0, '', 'CCTTT');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);

    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));    

    % case 6 - additions 1
    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    [V_ N1_ D_ N2_ J_] = deal(V0, 'GG', D0, '', J0);
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));
    
    %Cases 7/8/9 skipped

    % case 9 - additions  + deletions everywhere
    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    [V_ N1_ D_ N2_ J_] = deal('AAA', 'GG', D0, '', 'TTT');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));
    
    % case 10 - case 9 + coping with N nucleotides
    [V0 D0 J0] = deal('AAATTT', '', 'AANTTT');
    [V_ N1_ D_ N2_ J_] = deal('AAA', 'GGG', D0, '', 'ATTT');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));

    % case 11 - lowercase letters...
    [V0 D0 J0] = deal('TTTT', '', 'acaactggttcgactcctggggccaaggaaccctggtcaccgtctcctcag');
    [V_ N1_ D_ N2_ J_] = deal(V0, 'ACGGGACATGG', D0, '', 'CTGGTTCGACTCCTGGGGCCAAGGAACCCTGGTCACCGTCTCCTCAG');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(strcmp_(V,V_) && strcmp_(D,D_) && strcmp_(J,J_) && strcmp_(N1,N1_) && strcmp_(N2,N2_));    
    
    % case 12 - too long sequence?
    [V0 D0 J0] = deal('AAATTT', '', 'AAATTT');
    [V_ N1_ D_ N2_ J_] = deal(V0, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', D0, '', 'TTT');
    a = profileHMM_annotate_lambda([V_ N1_ D_ N2_ J_], V0, D0, J0);
    V = dict(a.V); D = dict(a.D); J = dict(a.J); N1 = dict(a.N1); N2 = dict(a.N2);
    assert(length([a.V_ N1 a.D_ N2 a.J_]) == length([V_ N1_ D_ N2_ J_]));

    fprintf('All Tests Passed.\n');
end

function res = strcmp_(V, V_)
    res = strcmp(V,V_) || (isempty(V) && isempty(V_));
end

function demo()
%%
addpath('../DPtrees/');
addpath(genpath('/afs/cs/u/joni/scratch/software/lightspeed'));
%%
    % choose a V D J
    rep.V = fastaread('V.fa');
    rep.D = fastaread('D.fa');
    rep.J = fastaread('J.fa');
    % choose V, D, J.
    v = ceil(length(rep.V)*rand);
    d = ceil(length(rep.D)*rand);
    j = ceil(length(rep.J)*rand);
    V_seq = rep.V(v).Sequence; 
    D_seq = rep.D(d).Sequence; 
    J_seq = rep.J(j).Sequence;

    params = profileHMM_get_params();

    fprintf('Generating sequence...\n');
    [seq V N1 D N2 J ] = profileHMM_gen(V_seq, D_seq, J_seq, params);
    fprintf('Annotating sequence...\n');
    [V_ N1_ D_ N2_ J_] = profileHMM_annotate(seq, V_seq, D_seq, J_seq, params);

    fprintf('V\n%s\n%s\n%s\n', V_seq, V, V_);
    fprintf('N1\n%s\n%s\n', N1, N1_);
    fprintf('D\n%s\n%s\n%s\n',D_seq, D, D_);
    fprintf('N2\n%s\n%s\n', N2, N2_);

    str_ = ['%' num2str(length(J_seq)) 's'];
    str = sprintf('J\n%s\n%s\n%s\n', str_, str_, str_);
    fprintf(str, J_seq, J, J_);

end

% function counts = seq_to_ind(seq)
%     if seq(1)>5
%         map('ACGTN') = 1:5;
%         seq = map(seq);
%     end
%     L = length(seq);
%     p = 0:5:(L-1)*5;
%     counts = false(5,L);
%     counts(seq+p) = 1;
% end



%% For D:
%        for i= (lV-min(lV,lP)+1):(L-lJ+min(lJ,lP))  %1:L 
%        for i=1:L 
%            [d_match(k+1,i+1) d_parent(k+1, i+1)] = ...
%                max(emit(D(k), X(i)) + [d_match(k, i)  d_jump(k,i)]);            
%            assert(n1(i) + d_pdel_prefix(k) == d_jump(k,i));
%	keyboard;
%            assert(d_match(k+1, i+1) == max(emit(D(k), X(i)) + [d_match(k, i)  d_jump(k,i)]));            	
%        end


%% For N1 (N2).
%     n1_match_ = -inf*ones(lN+1, L+1);
%     n1_match_(1,1+(1:lV)) = v;    
%     for k=1:lN
%         for i=lV-min(lV,lP)+1:min(lN+lV, L-lJ+min(lJ,lP)) %1:L
%             n1_match_(k+1,i+1) = n1_match_(k, i) + N_emit(k, X(i));
%         end
%     end
%     
%     assert(max(max(abs(n1_match-n1_match_))) < 1e-3);
