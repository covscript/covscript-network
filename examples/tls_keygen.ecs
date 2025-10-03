import gmssl

var key = null
system.console.echo(false)
loop
    system.out.print("Please set password: ")
    key = system.in.getline()
    if key.size < 6
        system.out.println("\nPassword must have 6 characters.")
        continue
    end
    system.out.print("\nRepeat password: ")
    if system.in.getline() != key
        system.out.println("\nPassword not match.")
        continue
    else
        system.out.print("\n")
        break
    end
end
system.console.echo(true)

var (pubkey, privkey) = gmssl.sm2_key_generate(key)

gmssl.sm2_pem_write("./sm2-pub.pem", pubkey)
gmssl.sm2_pem_write("./sm2.pem", privkey)

system.out.println("Keys saved to ./sm2-pub.pem and ./sm2.pem")

var pubkey_digest = gmssl.bytes_decode(gmssl.base64_encode(gmssl.sm3(pubkey)))

var ofs = iostream.fstream("./authorized_keys", iostream.openmode.app)
ofs.println(pubkey_digest)

system.out.println("Public Key saved to ./authorized_keys")
