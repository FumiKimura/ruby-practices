#! /usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'etc'
require 'date'

# lsコマンド通常表示モードの場合(longフォーマットでない場合)
def regular_format(list)
  return '' if list.empty? # もしディレクトリが空なら空の文字列を返す

  max_characters = list.max_by(&:size).size
  terminal_col_size = `tput cols`.to_i

  col_num = column_number(terminal_col_size, max_characters + 5)
  # 算出したcolumn数から行数を算出する
  row_num = (list.size % col_num).zero? ? (list.size / col_num) : (list.size / col_num) + 1
  split_by_col = list.each_slice(row_num).to_a

  result_to_print = []

  until split_by_col.join.empty?
    split_by_col.each do |col|
      col.empty? ? ' ' : result_to_print << col.shift.ljust(max_characters + 5)
    end
    puts result_to_print.join
    result_to_print.clear
  end
end

# ターミナルのcolumnの大きさに合わせて列数を変える
# もしcolumnの大きさが最大ファイル文字より小さければ列数1を返す
def column_number(terminal_size, max_char)
  col = terminal_size / max_char
  col.zero? ? 1 : col
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
  if (Date.today - day.to_date).to_i >= 180
    day.strftime('%b %d  %Y')
  else
    day.strftime('%b %d %H:%M')
  end
end

# longフォーマット用のメソッドはここまで
#====================

# ターミナルに出力させる前にonになっているオプションから
def print_list_content(long_format, reverse_sort, include_dot, target_dir)
  # 逆順で表示するかを判断する
  files = if reverse_sort
            Dir.glob('*', include_dot, base: target_dir).sort.reverse
          else
            Dir.glob('*', include_dot, base: target_dir).sort
          end

  # longフォーマットで表示するかを判断する
  long_format ? long_format(files, target_dir) : regular_format(files)
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
