%%  Add to path
set(0,'DefaultTextFontname', 'Lucida Console')
phylo_path = '/filesystem/u/liuyipei/joni/phylo/';
if strfind(pwd(), '/visionnfs/')
    phylo_path = regexprep(phylo_path, '/filesystem/', '/visionnfs/')
elseif strfind(pwd(), '/vision/')
    phylo_path = regexprep(phylo_path, '/filesystem/', '/vision/')
elseif strfind(pwd(), '/scail/')
    phylo_path = regexprep(phylo_path, '/filesystem/', '/scail/')
end

fprintf('phylo path: %s\n', phylo_path)
cd([phylo_path 'Fire'])
addpath(phylo_path, '-end');
addpath([phylo_path 'Fire'], '-end'); % fixes issues with affinegapmex/nwalign
addpath([phylo_path 'VDJ'], '-end');
addpath([phylo_path 'util'], '-end');

dbstop if error;
files = [dir('./output/*.fa.mat') dir('./output/*.fasta.mat')] % generate figures from all mat files
[~, username] = system('whoami');
liuyipei = isequal(username(1:8), 'liuyipei');
close all hidden
close all
cutoff_datenum = datenum(2012, 7, 24, 1, 0, 0);
dict = 'ACGT-';

% make a legend figure first
legend_figure_bg = biograph([0 1; 0 0]);
h=view(legend_figure_bg);
h.Nodes(1).UserData.Distribution = 0;
h.Nodes(2).UserData.Distribution = [1 1 1];
set(h.Nodes(2), 'Label', ...
    sprintf([...
    'Numbers on edges denote count of mutations. \n',...
    'Nodes are labeled with IDs and their sizes. \n',...
    'Meaning of slices, shown ccw, \nfrom dark blue to light blue: \n', ...
    '  4 days, 14 days, 6 months\n' ...
    ]));
h.CustomNodeDrawFcn = @(node) dist_node_draw(node);
jpg_file_name = './output/slices.legend.png';
f = get(h.hgAxes, 'Parent');
set(f, 'HandleVisibility', 'on');
set(f, 'Position', [1 1 800 600]);
f = get(h.hgAxes, 'Parent');
print(f, '-dpng', jpg_file_name);


hide_text_in_figures = true;

%find(arrayfun(@(x)isequal(files(x).name, 'IGHV3-74.IGHJ3.10.BFI-0000391.fa.clusterline.0001.fa.mat'), 1:363))
for j=1:length(files)
    if files(j).datenum < cutoff_datenum
        fprintf('skipping %s (due to datenum cutoff)\n', files(j).name);
        continue
    end

    %% setup
    close all
    close all hidden
    load(['./output/' files(j).name])
    
    a_tree_parents = a.tree(:, 1);
    a_tree_depths = zeros(1, length(a_tree_parents));
    for node = 1:length(a_tree_parents)
        parent = a_tree_parents(node);
        if parent == 0            
            a_tree_depths(node) = 0;
        else
            a_tree_depths(node) = 1 + a_tree_depths(parent);
        end
    end    
    [widest_depth, widest_depth_width] = mode(a_tree_depths);
    [~, widest_sibling_class] = mode(a_tree_parents);
    % descriptive statistics: max(depth), max(out degree), 
    % mean(node depth), mean node depth weighted by size
    description_textfile = [fasta_file '.description.txt']
    description_textfile = regexprep(description_textfile, '.*/', './output/');        
    [description_file_handle description_file_msg]= fopen(description_textfile, 'w+');
    fprintf(description_file_handle, '%s, %d\n', 'Max depth', max(a_tree_depths));
    fprintf(description_file_handle, '%s, %d\n', 'Size of largest sibling class', widest_sibling_class);
    fprintf(description_file_handle, '%s, %.3f\n', 'Mean depth', mean(a_tree_depths));
    fprintf(description_file_handle, '%s, %.3f\n', 'Read-count weighted mean depth', a_tree_depths*a.tree(:, 2)/a.tree(1,3));
    fprintf(description_file_handle, '%s, %d\n', 'Number of reads', a.tree(1,3));

    fclose(description_file_handle);
    
    
    header_textfile = [fasta_file '.header.txt']
    header_textfile = regexprep(header_textfile, '.*/', './output/');
    headers = {X(iz).Header}';
    sequences = {X(iz).Sequence}';
    [header_file_handle header_file_msg]= fopen(header_textfile, 'w+');
    fprintf(header_file_handle, 'header, node, sequence\n');
    for i = 1:length(headers)
        fprintf(header_file_handle, '%s, %d, %s\n', headers{i}, int16(a.t(i)), sequences{i});
    end
    fclose(header_file_handle);
    
    % compute the index of the final V base in the references (reference V,
    % and reference VJ) such that both references are populated at that
    % index. this is used to annotate the root germline node
    map('ACGTNRacgtn-') = [1:5 5 1:5 5];
    germline_vj_and_v_int = int16(cell2mat(cellfun(@(x) map(x(:)'), ...
        {upgma_alignment((end-2):end).Sequence}', ... % remove the concatenated germline_vj and the v-sequence
        'UniformOutput', 0)));
    last_full_refVandVJalign_pos = find(~max(germline_vj_and_v_int==5,[],1), 1, 'last');
    V_num_bases_ignored = sum(... % find the number of non-gaps from prefix that was dropped
        ismember(upgma_germline(1:(first_full_multialign_pos-1)), 'ATCGatcg'));
    V_num_bases_left = sum(... % find the number of non-gaps from prefix that was dropped
        ismember(upgma_germline(first_full_multialign_pos:end), 'ATCGatcg'));
    V_trimmed_germline.mutcount_end_indx = last_full_refVandVJalign_pos;
    
    % determine labels, based on visit number and year
    per_read_labels = 8 * ones(length(X), 1); % default value is 8 (dark dark red for 'unknown')
    
    assert(length(a.t) == length(X), 'a.t does not have the same length as X!')
    timestamp_strings = {'4_days','14_days', '6_mons'};
    for vi=1:size(X,1)
        for vj = 1:length(timestamp_strings)                    
            if strfind(X(vi).Header, timestamp_strings{vj}),
                per_read_labels(vi) = vj;
                continue
            end
        end
    end
    h = visualize_tree(a.tree, a.sequences, a.t, ...
        V_trimmed_clone, 1, V_trimmed_germline, ...
        per_read_labels);
    if hide_text_in_figures
        set(h, 'ShowWeights', 'off')
    end
    
    set(h.Nodes(1), 'Label', ...
        sprintf(['[1]\nGermline: %s\n',...
        '%d leading germline V bases were not used. ', ...
        '%d VJ bases were used in phylogeny.\n', ...
        'Germline V mutation count cutoff read index:%d\n%s'], ...
        concat_germline_vdj.Header, V_num_bases_ignored, V_num_bases_left, ...
        V_trimmed_germline.mutcount_end_indx, regexprep(fasta_file, '^.*/', '')));
    for k = 2:length(h.nodes)
        %set(h.nodes(k), 'Label', sprintf('%d nt diff', sum(h.nodes(k).Description == '>')), 'FontSize', 14)
        set(h.nodes(k), 'Label', sprintf('%d read(s)', sum(a.t == k)), 'FontSize', 18)
    end

        
    % loop over nodes and write the mode of the last field of the header, 
    % which represents (cdr3 in terms of aa)
    for i = 2:length(h.Nodes)
        indx = find(a.t == i);
        if hide_text_in_figures
            set(h.Nodes(i), 'Label', '');
            continue
        end
        
        if isempty(indx)
            continue
        end
        if length(indx) == 1 % one read
            [~,~,~, aa_cdr3_str_cells] = regexp(X(indx).Header, '[^|]*$');
            node_cdr3aa_consensus = aa_cdr3_str_cells{1};            
        else % multiple reads
            [~,~,~, aa_cdr3_str_cells] = regexp({X(indx).Header}', '[^|]*$');
            aa_cdr3_str_cells = cellfun(@(x)x{1}, aa_cdr3_str_cells, 'UniformOutput', false);
            node_cdr3aa_consensus = char(mode(double(cell2mat(aa_cdr3_str_cells))));            
        end
        node_cdr3aa_consensus_multiline = regexprep(['(' node_cdr3aa_consensus ')'], '(......)','$1\n');
        set(h.Nodes(i), 'Label', sprintf('%s\n%s', h.Nodes(i).Label, node_cdr3aa_consensus_multiline));
    end
    
    

    jpg_file_name = [fasta_file '.2.png'];
    if liuyipei, jpg_file_name = regexprep(jpg_file_name, '.*/', './output/'); end
    f = get(h.hgAxes, 'Parent');
    set(f, 'HandleVisibility', 'on');
    set(f, 'Visible', 'off');
    set(f, 'Position', [1 1 max(800, widest_depth_width * 70) max(600, (1+max(a_tree_depths))*80 )]);
    print(f, '-dpng', jpg_file_name);
    
    % save images
    show_read_alignment_to_germline(V_trimmed_clone, V_trimmed_germline, [], a.t);
    set(gcf, 'Position', [50 50 1000 1000]); 
    
    jpg_file_name = [fasta_file '.1.png'];
    if liuyipei, jpg_file_name = regexprep(jpg_file_name, '.*/', './output/'); end
    print(gcf, '-dpng', jpg_file_name);    

        
    node_textfile = [fasta_file '.node.txt']
    node_textfile = regexprep(node_textfile, '.*/', './output/');        
    [node_file_handle node_file_msg]= fopen(node_textfile, 'w+');
    fprintf(node_file_handle, 'node, parent, node_size, subtree_size, description, sequence\n');
    
    convert_padded_numeric_to_nuc = @(x) dict(x(x<5));
    for i = 1:length(h.Nodes)
        fprintf(node_file_handle, '%d, %d, %d, %d, %s, %s\n', i, a.tree(i,1), ...
            a.tree(i,2), a.tree(i,3), h.Nodes(i).Description, ...
            convert_padded_numeric_to_nuc(a.sequences(i,:)));
    end
    fclose(node_file_handle);
    
end
