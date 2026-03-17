package com.demo.awsdemo.service;

import com.demo.awsdemo.config.JwtUtil;
import com.demo.awsdemo.dto.AuthDto;
import com.demo.awsdemo.model.User;
import com.demo.awsdemo.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtUtil jwtUtil;
    private final AuthenticationManager authenticationManager;
    private final UserDetailsService userDetailsService;

    public AuthDto.AuthResponse register(AuthDto.RegisterRequest request) {
        // Check username exists
        if (userRepository.existsByUsername(request.getUsername())) {
            throw new RuntimeException("Username '" + request.getUsername() + "' already exists");
        }

        // Check email exists
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Email '" + request.getEmail() + "' already registered");
        }

        // Create new user
        User user = new User();
        user.setUsername(request.getUsername());
        user.setEmail(request.getEmail());
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setFullName(request.getFullName());
        user.setRole(User.Role.USER);

        userRepository.save(user);

        // Generate token
        UserDetails userDetails = userDetailsService.loadUserByUsername(user.getUsername());
        String token = jwtUtil.generateToken(userDetails);

        return new AuthDto.AuthResponse(
                token,
                user.getUsername(),
                user.getEmail(),
                user.getRole().name(),
                "Registration successful!"
        );
    }

    public AuthDto.AuthResponse login(AuthDto.LoginRequest request) {
        authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.getUsername(), request.getPassword())
        );

        User user = userRepository.findByUsername(request.getUsername())
                .orElseThrow(() -> new RuntimeException("User not found"));

        UserDetails userDetails = userDetailsService.loadUserByUsername(user.getUsername());
        String token = jwtUtil.generateToken(userDetails);

        return new AuthDto.AuthResponse(
                token,
                user.getUsername(),
                user.getEmail(),
                user.getRole().name(),
                "Login successful!"
        );
    }
}
