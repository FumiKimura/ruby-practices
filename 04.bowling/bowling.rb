#! /usr/bin/env ruby
# frozen_string_literal: true

score = ARGV[0]

score_arr = score.chars
shots = []

# 文字列から整数の配列に入れ替える
score_arr.each do |elem|
  shots << if elem == 'X'
             10
           else
             elem.to_i
           end
end

# フレームごとにスコアを分ける
frames = []
frame_count = 0

# 9フレーム目までをここで分ける
# 概要:shotsの配列から最初の2つを抜き取る
#   もし合計が10以下であれば、そのままframesへshift
#   もし合計が10であれば、[10,0] or [0,10] or [1-9,1-9]
#     [10,0]->10をshift, 0をpush, [0,10] or [1~9,1~9] -> そのままshift
#   もし合計が10以上であれば、[10,1~10]なので、10をshift,0をpush完全にストライク
while frame_count < 9

  first_two_in_shots = shots[0..1]

  frames << if first_two_in_shots.sum < 10 # ストライクでもスペアでもない
              shots.shift(2)
            elsif first_two_in_shots.sum == 10 # 配列の合計が10で、スペアがストライク
              if first_two_in_shots[0] == 10 # ストライクのケース [X,0]
                shots.shift(1).push(0)
              else
                shots.shift(2) # スペアのケース
              end
            else # 配列の合計が10以上で、完全にストライクのケース
              shots.shift(1).push(0)
            end

  frame_count += 1

end

# フレーム10の処理
frames << shots

total_score = 0

# 9フレーム目まのでの合計を計算
(0..frames.size - 2).each do |i|
  total_score += if frames[i][0] == 10 # 　iがストライクの場合
                   if frames[i + 1][0] == 10 && frames[i + 2].nil? # 9フレーム目からストライクが2回連続発生、10フレーム目の最初の２投を持ってくる
                     frames[i][0] + frames[i + 1][0] + frames[i + 1][1]
                   elsif frames[i + 1][0] == 10 # i(9フレーム以下)からストライクが2回連続発生する
                     frames[i][0] + frames[i + 1][0] + frames[i + 2][0]
                   else # iがストライクだが連続ストライクではない場合
                     frames[i][0] + frames[i + 1][0..1].sum
                   end
                 elsif frames[i].sum == 10 # スペアの場合
                   frames[i].sum + frames[i + 1][0]
                 else # その他
                   frames[i].sum
                 end
end

total_score += frames.last.sum # ここで１０フレーム目のスコアを足す

puts total_score
