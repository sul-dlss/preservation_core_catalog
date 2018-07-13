FactoryBot.define do
  factory :zip_part do
    md5 "00236a2ae558018ed13b5222ef1bd977"
    create_info "ok"
    parts_count 1
    size 1234
    status 'unreplicated'
    suffix { parts_count == 1 ? '.zip' : format('.z%02d', parts_count) }
    archive_preserved_copy
  end
end