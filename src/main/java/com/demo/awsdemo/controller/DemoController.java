package com.demo.awsdemo.controller;

import com.demo.awsdemo.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
public class DemoController {

    private final UserRepository userRepository;

    @GetMapping("/")
    public ResponseEntity<String> demo() {
        long userCount = userRepository.count();
        String html = """
            <!DOCTYPE html><html><head><title>AWS Demo</title><meta charset="UTF-8">
            <style>
            *{box-sizing:border-box;margin:0;padding:0}
            body{font-family:Arial,sans-serif;background:#f0f2f5;padding:20px}
            .container{max-width:800px;margin:0 auto}
            .card{background:white;padding:25px;border-radius:12px;box-shadow:0 2px 8px rgba(0,0,0,.1);margin-bottom:20px}
            h1{color:#1a1a2e;font-size:26px;margin-bottom:8px}
            h2{color:#16213e;font-size:18px;margin-bottom:15px}
            .badge{background:#27ae60;color:white;padding:3px 10px;border-radius:20px;font-size:13px}
            .stats{display:flex;gap:15px;margin-top:15px}
            .stat{flex:1;text-align:center;padding:15px;background:#f8f9fa;border-radius:8px}
            .stat-num{font-size:28px;font-weight:bold;color:#2c3e50}
            .stat-label{font-size:13px;color:#666;margin-top:4px}
            .endpoint{background:#f8f9fa;padding:10px 15px;border-left:4px solid #3498db;margin:8px 0;border-radius:4px;font-family:monospace;font-size:14px}
            .method{color:white;padding:2px 8px;border-radius:4px;font-size:12px;margin-right:8px;font-family:Arial}
            .post{background:#e67e22}.get{background:#27ae60}
            .form-row{display:flex;flex-wrap:wrap;gap:10px;margin-bottom:10px}
            input{padding:9px 12px;border:1px solid #ddd;border-radius:6px;font-size:14px;flex:1;min-width:150px}
            .btn-row{display:flex;gap:10px;flex-wrap:wrap;margin-top:5px}
            button{padding:9px 18px;color:white;border:none;border-radius:6px;cursor:pointer;font-size:14px}
            .btn-register{background:#27ae60}.btn-login{background:#3498db}.btn-profile{background:#9b59b6}
            pre{background:#1e1e2e;color:#cdd6f4;padding:15px;border-radius:8px;overflow-x:auto;font-size:13px;margin-top:15px;min-height:60px;line-height:1.6}
            .tech-stack{display:flex;gap:8px;flex-wrap:wrap;margin-top:10px}
            .tech{background:#e8f4fd;color:#2980b9;padding:4px 10px;border-radius:20px;font-size:13px}
            </style></head>
            <body><div class="container">
            <div class="card">
                <h2>🧪 Live Demo</h2>
                <div class="form-row">
                    <input id="username" placeholder="Username" value="demo_user"/>
                    <input id="email" placeholder="Email" value="demo@test.com"/>
                </div>
                <div class="form-row">
                    <input id="password" placeholder="Password" type="password" value="123456"/>
                    <input id="fullname" placeholder="Full Name" value="Demo User"/>
                </div>
                <div class="btn-row">
                    <button class="btn-register" onclick="register()">📝 Đăng ký</button>
                    <button class="btn-login" onclick="login()">🔐 Đăng nhập</button>
                    <button class="btn-profile" onclick="getProfile()">👤 Xem Profile</button>
                </div>
                <pre id="result">Nhấn một nút bên trên để thử API...</pre>
            </div>
            </div>
            <script>
            let token='';
            async function register(){
                setResult('Đang gửi request...');
                try{
                    const res=await fetch('/api/auth/register',{method:'POST',headers:{'Content-Type':'application/json'},
                    body:JSON.stringify({username:v('username'),email:v('email'),password:v('password'),fullName:v('fullname')})});
                    const data=await res.json();
                    if(data.token)token=data.token;
                    setResult(data);
                }catch(e){setResult({error:e.message});}
            }
            async function login(){
                setResult('Đang đăng nhập...');
                try{
                    const res=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},
                    body:JSON.stringify({username:v('username'),password:v('password')})});
                    const data=await res.json();
                    if(data.token)token=data.token;
                    setResult(data);
                }catch(e){setResult({error:e.message});}
            }
            async function getProfile(){
                if(!token){setResult({error:'Hãy đăng nhập trước!'});return;}
                try{
                    const res=await fetch('/api/users/me',{headers:{'Authorization':'Bearer '+token}});
                    setResult(await res.json());
                }catch(e){setResult({error:e.message});}
            }
            function v(id){return document.getElementById(id).value;}
            function setResult(data){document.getElementById('result').textContent=typeof data==='string'?data:JSON.stringify(data,null,2);}
            </script></body></html>
            """.formatted(userCount);
        return ResponseEntity.ok()
                .header("Content-Type", "text/html;charset=UTF-8")
                .body(html);
    }
}