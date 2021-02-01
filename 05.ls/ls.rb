#! /usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'etc'
require 'date'

# lsコマンド通常表示モードの場合(longフォーマットでない場合)
def format(list)
  max_characters = list.max_by(&:size).size
  terminal_col_size = `tput cols`.to_i

  col_num = column_number(terminal_col_size, max_characters)

  # 算出したcolumn数から行数を算出する
  row_num = (list.size % col_num).zero? ? list.size / col_num : (list.size / col_num) + 1

  split_by_col = list.each_slice(row_num).map { |elem| elem }
  result_to_print = ''

  # 行->列の順番に動いてファイル名をappendする。列の最後まで行ったら次の行へ動く。
  # 表計算シートを左から右に動かして、最後まで行ったら次の行の一番左からスタート
  row_num.times do |row_idx|
    col_num.times do |col_idx|
      filename = split_by_col[col_idx][row_idx].nil? ? '' : split_by_col[col_idx][row_idx].ljust(max_characters + 1)
      result_to_print += filename
    end
    puts result_to_print
    result_to_print = ''
  end
end

# ターミナルのcolumnの大きさに合わせて列数を変える(3行が最大)
def column_number(terminal_size, max_char)
  case terminal_size / (max_char + 1)
  when 1, 2, 3
    terminal_size / (max_char + 1)
  when 0
    1
  else
    3
  end
end

# longフォーマットで表示をするために整える
def long_format(filenames, path)
  files = []

  hardlink_char_maxsize = 0
  file_size_char_maxsize = 0

  # longフォーマットに必要なファイルの各項目を取得
  # 取得後に配列に挿入し全体を整えて
  filenames.each do |filename|
    file_obj = File::Stat.new(path + "/#{filename}")

    permission = convert_from_oct_to_ls(file_obj)
    hardlinks = file_obj.nlink.to_s
    owner_name = Etc.getpwuid(file_obj.uid).name
    group_name = Etc.getgrgid(file_obj.gid).name
    last_modified_time = display_last_modification_date(file_obj.mtime)
    file_size = file_obj.size.to_s

    # hardlinkの最大文字数を取得
    hardlink_char_maxsize = hardlinks.size if hardlinks.size > hardlink_char_maxsize

    # file sizeの最大文字数を取得
    file_size_char_maxsize = file_size.size if file_size.size > file_size_char_maxsize

    files << [permission, hardlinks, owner_name, group_name, file_size, last_modified_time, filename]
  end

  # hardlinkとfile sizeの最大文字数を整えながら出力
  files.each do |file|
    file[1] = file[1].to_s.rjust(hardlink_char_maxsize)
    file[4] = file[4].to_s.rjust(file_size_char_maxsize)
    puts file.join("\s\s")
  end
end

# longフォーマット用のメソッド集
#===================

# 8進数で出力されたファイルのパーミッションをlsフォーマットに変更する
def convert_from_oct_to_ls(file_obj)
  file_symbol = convert_ftype_to_symbol(file_obj.ftype)

  permission_arr = file_obj.mode.to_s(8).split('').last(3)

  # idx == 0 -> UID, idx == 1 -> GID, idx == 2 -> sticky
  permission = permission_arr.each.with_index.inject('') do |result, (val, idx)|
    result + special_authority(file_obj, idx, convert_int_to_rwx(val.to_i))
  end

  file_symbol + permission
end

# ftypeで取得したファイルタイプをlsフォーマットに変更する
def convert_ftype_to_symbol(file_type)
  { 'fifo' => 'p', 'characterSpecial' => 'c', 'directory' => 'd', 'blockSpecial' => 'b',
    'link' => '|', 'socket' => 's', 'file' => '-' }[file_type]
end

# 8進数のパーミッションをlsフォーマットに変更する
def convert_int_to_rwx(num)
  ['---', '--x', '-w-', '-wx', 'r--', 'r-x', 'rw-', 'rwx'][num]
end

def uid_special_char(obj, rwx_perm)
  return unless obj.setuid?

  rwx_perm[2] == 'x' ? 's' : 'S'
end

def gid_special_char(obj, rwx_perm)
  return unless obj.setgid?

  rwx_perm[2] == 'x' ? 's' : 'S'
end

def sticky_special_char(obj, rwx_perm)
  return unless obj.sticky?

  rwx_perm[2] == 'x' ? 't' : 'T'
end

# ファイルの特殊権限をlsのファイルパーミッションに表示させる処理
# 特殊権限の対象はuid, gid, スティッキーファイル
def special_authority(file_obj, idx, rwx)
  symbol_arr = rwx.split('')

  special_symbol = case idx
                   when 0 # UID
                     uid_special_char(file_obj, rwx)
                   when 1 # GID
                     gid_special_char(file_obj, rwx)
                   when 2 # sticky
                     sticky_special_char(file_obj, rwx)
                   end

  symbol_arr[2] = special_symbol unless special_symbol.nil?
  symbol_arr.join
end

# ファイルの最終変更日を表示する
# 6ヶ月以上のものは最終更新時間を表示しない、6ヶ月以内のモノは時間を表示
def display_last_modification_date(day)
  splitted_str = day.strftime('%b %d %H:%M %Y').split(' ')
  if (Date.today - day.to_date).to_i >= 180
    "#{splitted_str[0]}\s#{splitted_str[1]}\s\s#{splitted_str.last}"
  else
    "#{splitted_str[0]}\s#{splitted_str[1]}\s#{splitted_str[2]}"
  end
end

# longフォーマット用のメソッドはここまで
#====================

# ターミナルに出力させる前にonになっているオプションから
def print_list_content(long_format, reverse_sort, include_dot, target_dir)
  if long_format == true && reverse_sort == true
    long_format(Dir.glob('*', include_dot, base: target_dir).sort.reverse, target_dir)
  elsif long_format == true && reverse_sort == false
    long_format(Dir.glob('*', include_dot, base: target_dir).sort, target_dir)
  elsif long_format == false && reverse_sort == true # lオプション = falseなので3列
    format(Dir.glob('*', include_dot, base: target_dir).sort.reverse)
  else # long_format == false && reverse_sort == false, lオプション = falseなので３列
    format(Dir.glob('*', include_dot, base: target_dir).sort)
  end
end

opt = OptionParser.new
include_dot = 0 # flags = 0 is default for glob function
reverse_sort = false
long_format = false

# OptionParserのオプションを定義
#==========
opt.on('-a')  do
  include_dot = File::FNM_DOTMATCH
end

# 逆ソートで表示する
opt.on('-r') do
  reverse_sort = true
end

# longフォーマットで出力する。Longのリストで出力する。
# トータルのファイルサイズの後にlongを表示する
opt.on('-l') do
  long_format = true
end
#==========

pathname = opt.parse(ARGV)
target_directories = pathname.size.zero? ? ['.'] : pathname

# file/directory指定(複数指定も含む)は未実装
target_directories.each do |dir|
  print_list_content(long_format, reverse_sort, include_dot, dir)
end
