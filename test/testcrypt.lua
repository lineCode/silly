local crypt = require "crypt"
local P = require "print"

return function()
	local hmac_key = "test"
	local hmac_body = "helloworld"
	local res = crypt.hmac(hmac_key, hmac_body)
	print(string.format("hmac key:%s body:%s, res:", hmac_key, hmac_body))
	P.hex(hmac_body)
	P.hex(res)

	local aes1_key = "lilei"
	local aes1_body = "hello"
	local aes2_key = "hanmeimei"
	local aes2_body = "12345678910111213141516"

	local aes1_encode = crypt.aesencode(aes1_key, aes1_body)
	local aes2_encode = crypt.aesencode(aes2_key, aes2_body)
	local aes1_decode = crypt.aesdecode(aes1_key, aes1_encode)
	local aes2_decode = crypt.aesdecode(aes2_key, aes2_encode)
	assert(aes1_decode == aes1_body, "test decode fail")
	assert(aes2_decode == aes2_body, "test decode fail")
	assert(crypt.aesdecode(aes2_key, aes1_encode) ~= aes1_body, "test encrypt fail")
	assert(crypt.aesdecode("adsafdsafdsafds", aes1_encode) ~= aes1_body, "test encrypt fail")
	assert(crypt.aesdecode("fdsafdsafdsafdadfsa", aes2_encode) ~= aes2_body, "test encrypt fail")
	--test dirty data defend
	crypt.aesdecode("fdsafdsafdsafdsafda", aes2_body)
	print("testcrypt ok")
end

