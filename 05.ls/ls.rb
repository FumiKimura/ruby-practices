#! /usr/bin/env ruby
require 'optparse'
require 'etc'
require 'date'


#lsコマンド通常表示モードの場合(longフォーマットでない場合)
def format_col(file_list)

	#引数の配列に入っているファイル名の最大文字数を取得
	max_characters = file_list.max {|a, b| a.size <=> b.size}.size
	terminal_col_size = `tput cols`.to_i

	#ターミナルのcolumnの大きさに合わせて列数を変える(3行が最大)
	col_num = case terminal_col_size / (max_characters + 1)
		when 1, 2, 3
			terminal_col_size / (max_characters + 1)
		when 0
			1
		else
			3
		end

	#算出したcolumn数から行数を算出する
	row_num = if file_list.size % col_num == 0
			file_list.size / col_num
		else
			(file_list.size / col_num) + 1
		end

	#引数で与えられた配列を算出した行数でスライスする
  split_by_col = file_list.each_slice(row_num).map{|elem| elem}
	result_to_print = ''

	#ターミナルに結果を表示するループ
	#行->列の順番に動いてファイル名をappendする。列の最後まで行ったら次の行へ動く。
	#表計算シートを左から右に動かして、最後まで行ったら次の行の一番左からスタート
	row_num.times do |row_idx|
		col_num.times do |col_idx|
			filename = if split_by_col[col_idx][row_idx].nil?
					''
				else
					split_by_col[col_idx][row_idx].ljust(max_characters + 1)
				end
			result_to_print += filename
		end
		puts result_to_print
		result_to_print = ''
	end

end


#longフォーマットで表示をするために整える
def long_format(filenames, path)
	files = []

	hardlink_char_maxsize = 0
	file_size_char_maxsize = 0

	#longフォーマットに必要なファイルの各項目を取得
	#取得後に配列に挿入し全体を整えて
	filenames.each do |filename|
		file_obj = File::Stat.new(path + "/#{filename}")

		permission = convert_from_oct_to_ls(file_obj)
		hardlinks = file_obj.nlink.to_s
		owner_name = Etc.getpwuid(file_obj.uid).name
		group_name = Etc.getgrgid(file_obj.gid).name
		last_modified_time = display_last_modification_date(file_obj.mtime)
		file_size = file_obj.size.to_s

		#hardlinkの最大文字数を取得
		if hardlinks.size > hardlink_char_maxsize
			hardlink_char_maxsize = hardlinks.size
		end

		#file sizeの最大文字数を取得
		if file_size.size > file_size_char_maxsize
			file_size_char_maxsize = file_size.size
		end

		file_info = [permission, hardlinks, owner_name, group_name, file_size, last_modified_time, filename]
		files << file_info
	end

	#hardlinkとfile sizeの最大文字数を整えながら出力
	files.each do |file|
		file[1] = file[1].to_s.rjust(hardlink_char_maxsize)
		file[4] = file[4].to_s.rjust(file_size_char_maxsize)
		puts file.join("\s\s")
	end

end


#longフォーマット用のメソッド集
#===================

#8進数で出力されたファイルのパーミッションをlsフォーマットに変更する
def convert_from_oct_to_ls(file_obj)
	file_symbol = convert_ftype_to_symbol(file_obj.ftype)

  permission_arr = file_obj.mode.to_s(8).split('').last(3)

  permission = permission_arr.each.with_index.inject('') do |result, (val, idx)|
		result + special_authority(file_obj, idx, convert_int_to_rwx(val.to_i))
	end

	return file_symbol + permission

end

#ftypeで取得したファイルタイプをlsフォーマットに変更する
def convert_ftype_to_symbol(file_type)
		{'fifo'=>'p', 'characterSpecial'=>'c', 'directory'=>'d', 'blockSpecial'=>'b',
			'link'=>'|', 'socket'=>'s', 'file'=>'-'}[file_type]
end

#8進数のパーミッションをlsフォーマットに変更する
def convert_int_to_rwx(num)
	['---','--x','-w-','-wx','r--','r-x','rw-','rwx'][num]
end

#ファイルの特殊権限をlsのファイルパーミッションに表示させる処理
#特殊権限の対象はuid, gid, スティッキーファイル
def special_authority(file_obj, idx, rwx)

	symbol_arr = rwx.split('')

	special_symbol = case idx
	when 0 #SUID
		if file_obj.setuid?
			rwx[2] == 'x' ? 's': 'S'
		end
	when 1 #SGID
		if file_obj.setgid?
			rwx[2] == 'x' ? 's': 'S'
		end
	when 2 #sticky
		if file_obj.sticky?
			rwx[2] == 'x' ? 't': 'T'
		end
	end

	symbol_arr[2] = special_symbol if !special_symbol.nil?
	return symbol_arr.join

end

#ファイルの最終変更日を表示する
#6ヶ月以上のものは最終更新時間を表示しない、6ヶ月以内のモノは時間を表示
def display_last_modification_date(day)
  splitted_str = day.strftime("%b %d %H:%M %Y").split(' ')
  if (Date.today - day.to_date).to_i >= 180
    "#{splitted_str[0]}\s#{splitted_str[1]}\s\s#{splitted_str.last}"
  else
    "#{splitted_str[0]}\s#{splitted_str[1]}\s#{splitted_str[2]}"
  end
end

#longフォーマット用のメソッドはここまで
#====================

#ターミナルに出力させる前にonになっているオプションから
def print_list_content(long_format, reverse_sort, include_dot, target_dir)

		if long_format == true && reverse_sort == true
			long_format(Dir.glob('*', flags=include_dot, base: target_dir).sort.reverse, target_dir)
		elsif long_format == true && reverse_sort == false
			long_format(Dir.glob('*', flags=include_dot, base: target_dir).sort, target_dir)
		elsif long_format == false && reverse_sort == true #lオプション = falseなので3列
			 format_col(Dir.glob('*', flags=include_dot, base: target_dir).sort.reverse)
		else #long_format == false && reverse_sort == false, lオプション = falseなので３列
			 format_col(Dir.glob('*', flags=include_dot, base: target_dir).sort)
		end
end

opt = OptionParser.new
include_dot = 0 #flags = 0 is default for glob function
reverse_sort = false
long_format = false

#OptionParserのオプションを定義
#==========
opt.on('-a'){
	include_dot = File::FNM_DOTMATCH
}

#逆ソートで表示する
opt.on('-r'){
	reverse_sort = true
}

#longフォーマットで出力する。Longのリストで出力する。
#トータルのファイルサイズの後にlongを表示する
opt.on('-l'){
	long_format = true
}
#==========

pathname = opt.parse(ARGV)
target_directories = pathname.size == 0 ? ['.']: pathname

#file/directory指定(複数指定も含む)は未実装
target_directories.each do |dir|
	print_list_content(long_format, reverse_sort, include_dot, dir)
end
