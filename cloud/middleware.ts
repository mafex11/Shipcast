import { auth } from "@/lib/auth";

export default auth((req) => {
  if (req.nextUrl.pathname.startsWith("/dashboard") && !req.auth) {
    return Response.redirect(new URL("/api/auth/signin", req.url));
  }
});

export const config = {
  matcher: ["/dashboard/:path*"],
};
